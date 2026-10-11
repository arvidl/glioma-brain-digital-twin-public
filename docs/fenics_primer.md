# FEniCSx (FEniCS Next Generation) Primer

A practical introduction to finite element methods for solving PDEs on complex domains, with applications to brain mechanics.

## What FEniCSx Does

FEniCSx is a modern Python-C++ library for automating finite element method (FEM) workflows:

1. **Mesh generation**: Create/load 3D unstructured meshes (tetrahedra, hexahedra).
2. **Function spaces**: Define spaces of basis functions (Lagrange, Raviart-Thomas, etc.).
3. **Variational formulation**: Specify weak form of a PDE.
4. **Assembly & solve**: Automatic code generation → efficient sparse linear algebra.
5. **Visualization**: Paraview-compatible output for postprocessing.

**Core philosophy**: Separate mathematical specification (UFL) from discretization and linear algebra (DOLFIN).

## Key Concepts

### Mesh

Represent a spatial domain Ω as unstructured tetrahedral/hex grid. Created via:

- **Gmsh**: external meshing tool, import .msh file
- **Built-in**: `dolfinx.mesh.create_*` (unit cube, interval, etc.)
- **External library**: convert from DICOM/NIfTI via custom scripts

```python
from dolfinx import mesh
domain = mesh.create_unit_cube(MPI.COMM_WORLD, 10, 10, 10)
```

### Function Space

A Hilbert space of piecewise polynomial functions defined on the mesh. Specified by:

- **Mesh**: Ω
- **Element family**: Lagrange, DG (discontinuous Galerkin), Raviart-Thomas, etc.
- **Polynomial degree**: k ∈ {1, 2, 3, ...}

```python
from dolfinx.fem import FunctionSpace
V = FunctionSpace(domain, ("Lagrange", 2))  # P2 space
```

Dimension: ≈ number of nodes (linear) or higher (quadratic).

### Variational Form

A PDE is cast as a **weak form**:

Find u ∈ V such that a(u, v) = L(v) for all v ∈ V̂ (test space).

where:
- **a(u, v)**: bilinear form (left-hand side)
- **L(v)**: linear form (right-hand side)

**Example**: Poisson equation $-\nabla^2 u = f$ on Ω, u = 0 on ∂Ω becomes:

Find u ∈ V such that:
$$\int_\Omega \nabla u \cdot \nabla v \, dx = \int_\Omega f v \, dx \quad \forall v \in V$$

via Green's theorem (integration by parts).

### Boundary Conditions

Dirichlet (u = g on boundary), Neumann (∂u/∂n = h), or mixed.

```python
from dolfinx.fem import dirichletbc
uD = Function(V)  # prescribed value
uD.x.array[:] = 0.0
bc = dirichletbc(uD, dolfinx.fem.locate_dofs_topological(V, 1, boundary_facets))
```

## Example: 1D Poisson Equation in FEniCSx

**Problem**: Solve $-u'' = 1$ on (0, 1) with u(0) = u(1) = 0.

**Analytical solution**: $u(x) = x(1-x)/2$.

```python
import numpy as np
from dolfinx import mesh, fem, io, plot
from dolfinx.fem import Function, FunctionSpace, form, dirichletbc
from petsc4py.PETSc import ScalarType
import ufl

# 1D mesh: interval [0, 1] with 100 elements
domain = mesh.create_interval(MPI.COMM_WORLD, 100)

# Function space: piecewise linear (P1)
V = FunctionSpace(domain, ("Lagrange", 1))

# Trial (u) and test (v) functions
u = ufl.TrialFunction(V)
v = ufl.TestFunction(V)

# Bilinear and linear forms
a = ufl.dot(ufl.grad(u), ufl.grad(v)) * ufl.dx
L = fem.Constant(domain, ScalarType(1.0)) * v * ufl.dx

# Boundary conditions: u = 0 at both ends
def boundary_ends(x):
    return np.logical_or(np.abs(x[0]) < 1e-10, np.abs(x[0] - 1.0) < 1e-10)

boundary_facets = mesh.locate_entities_boundary(domain, 0, boundary_ends)
boundary_dofs = fem.locate_dofs_topological(V, 0, boundary_facets)

uD = Function(V)
uD.x.array[:] = 0.0
bc = dirichletbc(uD, boundary_dofs)

# Assemble and solve
problem = fem.petsc.LinearProblem(a, L, bcs=[bc], petsc_options={"ksp_type": "preonly", "pc_type": "lu"})
uh = problem.solve()

# Plot
import pyvista as pv
plotter = pv.Plotter()
# (plotting code omitted for brevity)
```

## Key UFL Operators

| Operator | Meaning |
|----------|---------|
| `ufl.grad(u)` | ∇u |
| `ufl.div(u)` | ∇·u |
| `ufl.curl(u)` | ∇×u |
| `ufl.inner(u, v)` | u·v (scalar product) |
| `ufl.dot(u, v)` | u·v or matrix product |
| `ufl.outer(u, v)` | u⊗v (dyadic) |
| `ufl.nabla_grad(u)` | ∇u (alias for grad) |
| `ufl.sym(A)` | (A+A^T)/2 (symmetric part) |
| `ufl.dx` | volume integral ∫_Ω |
| `ufl.ds` | boundary integral ∫_∂Ω |

## Relevant Brain Mechanics Equations

### Poroelasticity (Darcy-Stokes coupling)

Tissue as porous solid saturated with interstitial fluid. Relevant for tumor edema and cerebrospinal fluid (CSF) flow.

**Equations**:
$$\rho \frac{\partial^2 \mathbf{u}}{\partial t^2} = \nabla \cdot \boldsymbol{\sigma} - \alpha \nabla p + \mathbf{f}$$

$$\frac{\partial}{\partial t}(\phi c_f + \alpha S_u) p + \nabla \cdot (\mathbf{q}) = 0$$

where:
- $\mathbf{u}$: solid displacement
- $p$: fluid pressure
- $\boldsymbol{\sigma}$: solid stress
- $\mathbf{q} = -\mathbf{K} \nabla p$: Darcy flow
- $\alpha$: Biot coefficient
- $\phi$: porosity

### Hyperelastic Soft Tissue

Brain tissue is nonlinear elastic. Strain energy density:

$$W(\mathbf{F}) = \frac{\mu}{2}(I_1 - 3) + \frac{\lambda}{2}(\log J)^2$$

where $\mathbf{F}$ is deformation gradient, $I_1 = \text{tr}(\mathbf{C})$, $J = \det(\mathbf{F})$.

Stress: $\boldsymbol{\sigma} = \frac{1}{J} \mathbf{F} \frac{\partial W}{\partial \mathbf{F}} \mathbf{F}^T$ (Cauchy).

### Reaction-Diffusion (Tumor Growth)

$$\frac{\partial c}{\partial t} = D \nabla^2 c + \rho c(1 - c) - \mu c$$

where $c$ is cell density (0 ≤ c ≤ 1), D is diffusivity, ρ is proliferation, μ is death rate.

**In FEniCSx**:

```python
# Mixed function space: displacement and pressure (u, p)
P1 = ufl.VectorElement("Lagrange", domain.ufl_cell(), 1)
P0 = ufl.FiniteElement("DG", domain.ufl_cell(), 0)
ME = ufl.MixedElement([P1, P0])
V = FunctionSpace(domain, ME)
up = Function(V)
u, p = ufl.split(up)

# Hyperelasticity
I = ufl.Identity(3)
F = I + ufl.grad(u)
J = ufl.det(F)
C = F.T * F
I1 = ufl.tr(C)

mu, lam = fem.Constant(domain, ScalarType(1.0)), fem.Constant(domain, ScalarType(1.0))
W = (mu/2) * (I1 - 3) + (lam/2) * ufl.ln(J)**2
P = ufl.diff(W, F)  # first P-K stress

# Variational form
v, q = ufl.TestFunctions(V)
F_form = ufl.inner(P, ufl.grad(v)) * ufl.dx - ufl.inner(p, J - 1) * q * ufl.dx
```

## Tips for Performance on Different Platforms

### Apple Silicon (M1/M2/M3)

- **Native ARM support**: Use conda-forge builds (pre-compiled).
  ```bash
  conda create -n fenics-arm -c conda-forge fenics-dolfinx
  ```
- **Memory bandwidth advantage**: Apple Silicon has high memory bandwidth (>100 GB/s) → FEM assembly fast relative to solve.
- **Avoid x86 Rosetta translation**: Use native packages only.
- **Threading**: MPI communication may be slow on GPU-less systems; use shared-memory parallelism (`petsc4py` with `-np 1`).

### Linux + CUDA

- **CUDA-aware MPI**: Use `mpi4py` built with CUDA support for GPU-to-GPU communication.
- **PETSc GPU solvers**: Build PETSc with CUDA, enable `-mat_type aijcusparse -vec_type cuda`.
- **Multi-GPU**: `mpirun -np 4` (4 GPUs) automatically distributes mesh/matrix partitions.
- **Memory pools**: Pre-allocate GPU memory to avoid fragmentation.
- **Benchmark**: Profile assembly vs. solve; assembly often CPU-bound, solve GPU-accelerated.

### General Optimization

- **Mesh quality**: Higher aspect ratios → worse conditioning → more iterations.
- **Quadrature degree**: Auto-determined by FEniCSx; can override with `metadata={"quadrature_degree": 3}`.
- **Matrix format**: `aij` (CSR) best for sparse kernels; switch to `dense` only for small systems.
- **Solver choice**: GMRES + algebraic multigrid (AMG) preconditioner for large systems; LU for small (N < 10^5).

