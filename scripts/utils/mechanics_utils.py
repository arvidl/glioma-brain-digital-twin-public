"""
mechanics_utils.py
──────────────────
FEniCSx helpers for setting up brain mechanics problems.

Provides functions to:
  – create simple 3-D brain-like meshes
  – assign tissue material properties
  – solve linear / hyperelastic problems
  – post-process displacement and stress

Usage
-----
>>> from scripts.utils.mechanics_utils import BrainMesh, LinearBrainModel
>>> mesh = BrainMesh.ellipsoid(radii=(0.09, 0.07, 0.06), resolution=20)
>>> model = LinearBrainModel(mesh)
>>> model.solve()
"""

from __future__ import annotations

import numpy as np

# FEniCSx imports (deferred so that the module can still be imported even
# if FEniCSx is not installed – notebooks will raise a helpful error at the
# point of use).
_DOLFINX_AVAILABLE = False
try:
    import dolfinx  # noqa: F401

    _DOLFINX_AVAILABLE = True
except ImportError:
    pass


def _require_dolfinx():
    if not _DOLFINX_AVAILABLE:
        raise ImportError(
            "FEniCSx (dolfinx) is required for mechanics notebooks.\n"
            "Install with:  conda install -c conda-forge fenics-dolfinx\n"
            "See INSTALLATION.md for platform-specific instructions."
        )


# ─── Material properties ──────────────────────────────────────────────────────

# Approximate material parameters for brain tissue (in SI units: Pa, m).
# References:
#   Miga et al. (2001), Weickenmeier et al. (2017), Budday et al. (2019)
TISSUE_PROPERTIES = {
    "white_matter": {"E": 2500.0, "nu": 0.45, "rho": 1040.0},
    "gray_matter": {"E": 1500.0, "nu": 0.45, "rho": 1040.0},
    "glioma_II": {"E": 8000.0, "nu": 0.40, "rho": 1050.0},
    "glioma_III": {"E": 15000.0, "nu": 0.38, "rho": 1060.0},
    "edema": {"E": 500.0, "nu": 0.49, "rho": 1020.0},
    "csf": {"E": 100.0, "nu": 0.49, "rho": 1007.0},
}


def lame_parameters(E: float, nu: float) -> tuple[float, float]:
    """Convert Young's modulus E and Poisson ratio nu to Lamé parameters λ, μ."""
    lam = E * nu / ((1 + nu) * (1 - 2 * nu))
    mu = E / (2 * (1 + nu))
    return lam, mu


# ─── Mesh helpers ─────────────────────────────────────────────────────────────


class BrainMesh:
    """Factory for simple brain-like FEniCSx meshes."""

    @staticmethod
    def box(
        dims: tuple[float, float, float] = (0.18, 0.14, 0.12),
        resolution: int = 10,
    ):
        """Create a box mesh approximating brain dimensions (m)."""
        _require_dolfinx()
        import numpy as np
        from dolfinx.mesh import CellType, create_box
        from mpi4py import MPI

        mesh = create_box(
            MPI.COMM_WORLD,
            [np.zeros(3), np.array(dims)],
            [resolution, resolution, resolution],
            CellType.tetrahedron,
        )
        return mesh

    @staticmethod
    def sphere(radius: float = 0.085, resolution: int = 15):
        """Create a spherical mesh of given radius."""
        _require_dolfinx()
        try:
            import gmsh
            from dolfinx.io import gmshio
            from mpi4py import MPI
        except ImportError:
            raise ImportError("gmsh and mpi4py are required for spherical meshes")

        gmsh.initialize()
        gmsh.model.add("brain_sphere")
        gmsh.model.occ.addSphere(0, 0, 0, radius)
        gmsh.model.occ.synchronize()
        gmsh.option.setNumber("Mesh.MeshSizeMax", radius / resolution)
        gmsh.model.mesh.generate(3)
        mesh, _, _ = gmshio.model_to_mesh(gmsh.model, MPI.COMM_WORLD, 0, gdim=3)
        gmsh.finalize()
        return mesh

    @staticmethod
    def ellipsoid(
        radii: tuple[float, float, float] = (0.09, 0.07, 0.06),
        resolution: int = 15,
    ):
        """Create an ellipsoidal mesh (more brain-shaped than a sphere)."""
        _require_dolfinx()
        try:
            import gmsh
            from dolfinx.io import gmshio
            from mpi4py import MPI
        except ImportError:
            raise ImportError("gmsh and mpi4py are required for ellipsoidal meshes")

        a, b, c = radii
        gmsh.initialize()
        gmsh.model.add("brain_ellipsoid")
        # Create sphere then scale
        tag = gmsh.model.occ.addSphere(0, 0, 0, 1.0)
        gmsh.model.occ.dilate([(3, tag)], 0, 0, 0, a, b, c)
        gmsh.model.occ.synchronize()
        gmsh.option.setNumber("Mesh.MeshSizeMax", min(radii) / resolution)
        gmsh.model.mesh.generate(3)
        mesh, _, _ = gmshio.model_to_mesh(gmsh.model, MPI.COMM_WORLD, 0, gdim=3)
        gmsh.finalize()
        return mesh


# ─── Linear elasticity model ──────────────────────────────────────────────────


class LinearBrainModel:
    """Isotropic linear-elastic model for brain tissue mechanics.

    Solves:
        ∇·σ(u) + f = 0   in Ω
        u = 0            on ∂Ω_D   (Dirichlet – fixed skull)
        σ·n = t          on ∂Ω_N   (Neumann – surface traction)

    where σ = λ tr(ε) I + 2μ ε  and  ε = ½(∇u + (∇u)ᵀ).

    Parameters
    ----------
    mesh      : dolfinx.mesh.Mesh
    tissue    : str, key in TISSUE_PROPERTIES
    body_force: (fx, fy, fz) in N/m³, default gravity
    """

    def __init__(
        self,
        mesh,
        tissue: str = "white_matter",
        body_force: tuple[float, float, float] = (0.0, 0.0, -9.81 * 1040.0),
    ):
        _require_dolfinx()
        self.mesh = mesh
        props = TISSUE_PROPERTIES[tissue]
        self.lam, self.mu = lame_parameters(props["E"], props["nu"])
        self.body_force = body_force
        self.u_solution = None

    def solve(self, verbose: bool = True):
        """Assemble and solve the linear elasticity system."""
        _require_dolfinx()
        import dolfinx.fem as fem
        import dolfinx.fem.petsc as petsc_fem
        import ufl
        from petsc4py import PETSc
        from ufl import (
            TestFunction,
            TrialFunction,
            dx,
            grad,
            inner,
            sym,
            tr,
        )

        mesh = self.mesh
        lam = self.lam
        mu = self.mu

        # Function space (P2 vector elements)
        V = fem.VectorFunctionSpace(mesh, ("Lagrange", 2))

        # Strain and stress tensors
        def eps(v):
            return sym(grad(v))

        def sigma(v):
            return lam * tr(eps(v)) * ufl.Identity(len(v)) + 2 * mu * eps(v)

        u = TrialFunction(V)
        v = TestFunction(V)
        f = fem.Constant(mesh, PETSc.ScalarType(self.body_force))

        a = inner(sigma(u), eps(v)) * dx
        L = inner(f, v) * dx

        # Dirichlet: fix all boundary nodes
        def boundary(x):
            return np.full(x.shape[1], True)

        bc_dofs = fem.locate_dofs_geometrical(V, boundary)
        u0 = fem.Function(V)
        u0.x.array[:] = 0
        bc = fem.dirichletbc(u0, bc_dofs)

        # Solve
        problem = petsc_fem.LinearProblem(
            a, L, bcs=[bc], petsc_options={"ksp_type": "preonly", "pc_type": "lu"}
        )
        self.u_solution = problem.solve()
        if verbose:
            print(
                f"[LinearBrainModel] Solved. |u|_max = "
                f"{np.max(np.abs(self.u_solution.x.array)):.4e} m"
            )
        return self.u_solution

    def von_mises_stress(self) -> np.ndarray:
        """Compute von Mises stress from the solution."""
        _require_dolfinx()
        import dolfinx.fem as fem
        from ufl import Identity, grad, inner, sqrt, sym, tr

        u = self.u_solution
        lam = self.lam
        mu = self.mu

        def eps(v):
            return sym(grad(v))

        def sigma(v):
            return lam * tr(eps(v)) * Identity(len(v)) + 2 * mu * eps(v)

        s = sigma(u) - (1.0 / 3) * tr(sigma(u)) * Identity(len(u))
        vm = sqrt(3.0 / 2 * inner(s, s))

        W = fem.FunctionSpace(self.mesh, ("DG", 0))
        vm_expr = fem.Expression(vm, W.element.interpolation_points())
        vm_func = fem.Function(W)
        vm_func.interpolate(vm_expr)
        return vm_func


# ─── DTI-informed material properties ─────────────────────────────────────────


def assign_material_properties_from_dti(
    mesh,
    cell_tags,
    fa_nii_path: str,
    md_nii_path: str,
    tumor_nii_path: str | None = None,
):
    """Map DTI-derived FA and MD onto spatially varying Lamé parameters.

    For each mesh cell, the FA and MD values are sampled from the
    corresponding NIfTI volumes at the cell centroid.  These are then
    converted to Young's modulus E(x) and Poisson ratio ν(x) via
    empirically motivated interpolation:

      E(x) = E_base(tissue) × (1 + α × FA(x))
      ν(x) = ν_base(tissue) × (1 + β × MD(x) / MD_ref)

    where E_base and ν_base come from TISSUE_PROPERTIES, α and β are
    scaling coefficients, and MD_ref is a reference diffusivity.

    Tumor cells are overridden with glioma material properties regardless
    of local DTI values (tumor infiltration corrupts diffusion signal).

    Parameters
    ----------
    mesh        : dolfinx.mesh.Mesh
    cell_tags   : int32 array of tissue tags per cell (from create_brain_mesh)
    fa_nii_path : path to FA map (in T1w space, same as aparc+aseg)
    md_nii_path : path to MD map (in T1w space, same as aparc+aseg)
    tumor_nii_path : optional path to binary tumor mask

    Returns
    -------
    lam_values : (ncells,) array of first Lamé parameter λ per cell
    mu_values  : (ncells,) array of shear modulus μ per cell
    """
    _require_dolfinx()
    import nibabel as nib

    # Tissue tag constants (must match create_brain_mesh.py)
    TAG_WM = 1
    TAG_GM = 2
    TAG_TUMOR = 3
    TAG_CSF = 4
    TAG_DEEP = 5

    fa_img = nib.load(fa_nii_path)
    md_img = nib.load(md_nii_path)
    fa_data = np.asarray(fa_img.dataobj).astype(np.float32)
    md_data = np.asarray(md_img.dataobj).astype(np.float32)
    inv_affine = np.linalg.inv(fa_img.affine)

    # Cell centroids in world coordinates
    tdim = mesh.topology.dim
    mesh.topology.create_connectivity(tdim, 0)
    num_cells = mesh.topology.index_map(tdim).size_local
    geometry = mesh.geometry.x
    cell_to_vertex = mesh.topology.connectivity(tdim, 0)

    centroids = np.zeros((num_cells, 3))
    for i in range(num_cells):
        verts = cell_to_vertex.links(i)
        centroids[i] = geometry[verts].mean(axis=0)

    # World → voxel coordinates
    vox_coords = (inv_affine[:3, :3] @ centroids.T).T + inv_affine[:3, 3]
    vox_ijk = np.clip(
        np.round(vox_coords).astype(int),
        [0, 0, 0],
        np.array(fa_data.shape) - 1,
    )

    fa_at_cells = fa_data[vox_ijk[:, 0], vox_ijk[:, 1], vox_ijk[:, 2]]
    md_at_cells = md_data[vox_ijk[:, 0], vox_ijk[:, 1], vox_ijk[:, 2]]

    # Clamp FA to [0, 1] and MD to positive values
    fa_at_cells = np.clip(fa_at_cells, 0.0, 1.0)
    md_at_cells = np.clip(md_at_cells, 1e-6, None)

    # Reference MD for scaling: typical brain parenchyma ~0.8e-3 mm²/s
    MD_REF = 0.8e-3

    # Base properties per tissue tag
    tag_to_props = {
        TAG_WM: TISSUE_PROPERTIES["white_matter"],
        TAG_GM: TISSUE_PROPERTIES["gray_matter"],
        TAG_TUMOR: TISSUE_PROPERTIES["glioma_II"],
        TAG_CSF: TISSUE_PROPERTIES["csf"],
        TAG_DEEP: TISSUE_PROPERTIES["gray_matter"],  # approximate
    }

    # FA modulates stiffness: higher FA → stiffer (more aligned fibers)
    # MD modulates compressibility: higher MD → more fluid-like (higher ν)
    ALPHA_FA = 0.8  # stiffness scaling coefficient
    BETA_MD = 0.05  # compressibility scaling coefficient

    E_arr = np.zeros(num_cells, dtype=np.float64)
    nu_arr = np.zeros(num_cells, dtype=np.float64)

    for i in range(num_cells):
        tag = int(cell_tags[i])
        props = tag_to_props.get(tag, TISSUE_PROPERTIES["gray_matter"])
        E_base = props["E"]
        nu_base = props["nu"]

        if tag == TAG_TUMOR:
            # Override: use tumor properties, ignore local DTI
            E_arr[i] = E_base
            nu_arr[i] = nu_base
        elif tag == TAG_CSF:
            E_arr[i] = E_base
            nu_arr[i] = nu_base
        else:
            # DTI-modulated properties
            fa = fa_at_cells[i]
            md = md_at_cells[i]
            E_arr[i] = E_base * (1.0 + ALPHA_FA * fa)
            nu_arr[i] = min(nu_base * (1.0 + BETA_MD * md / MD_REF), 0.4999)

    lam_arr = E_arr * nu_arr / ((1 + nu_arr) * (1 - 2 * nu_arr))
    mu_arr = E_arr / (2 * (1 + nu_arr))

    print(f"[DTI material mapping] {num_cells} cells")
    print(f"  E range:  [{E_arr.min():.0f}, {E_arr.max():.0f}] Pa")
    print(f"  ν range:  [{nu_arr.min():.4f}, {nu_arr.max():.4f}]")
    print(f"  λ range:  [{lam_arr.min():.0f}, {lam_arr.max():.0f}] Pa")
    print(f"  μ range:  [{mu_arr.min():.0f}, {mu_arr.max():.0f}] Pa")

    return lam_arr, mu_arr


def add_tumor_subregion(
    mesh,
    tumor_center: tuple[float, float, float],
    tumor_radius: float,
    tissue_background: str = "white_matter",
    tissue_tumor: str = "glioma_II",
):
    """Mark cells inside a spherical tumor subregion for inhomogeneous material.

    Returns
    -------
    cell_tags : MeshTags marking background (1) and tumor (2) cells.
    props     : dict mapping tag → (lam, mu)
    """
    _require_dolfinx()
    import dolfinx.mesh as dmesh

    cx, cy, cz = tumor_center
    r = tumor_radius

    def tumor_cells(x):
        return (x[0] - cx) ** 2 + (x[1] - cy) ** 2 + (x[2] - cz) ** 2 < r**2

    tumor_indices = dmesh.locate_entities(mesh, mesh.topology.dim, tumor_cells)
    all_cells = np.arange(mesh.topology.index_map(mesh.topology.dim).size_local, dtype=np.int32)
    values = np.ones(len(all_cells), dtype=np.int32)
    values[np.isin(all_cells, tumor_indices)] = 2

    cell_tags = dmesh.meshtags(mesh, mesh.topology.dim, all_cells, values)

    props = {
        1: lame_parameters(**{k: TISSUE_PROPERTIES[tissue_background][k] for k in ("E", "nu")}),
        2: lame_parameters(**{k: TISSUE_PROPERTIES[tissue_tumor][k] for k in ("E", "nu")}),
    }
    return cell_tags, props
