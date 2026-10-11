"""
Environment checker script for Finse 2026.

Verifies that all required and optional packages are available,
and prints a diagnostic report.

Can be invoked as: python -m scripts.check_env or check-env (via entry point)
"""

import sys
from importlib.util import find_spec
import platform


REQUIRED = [
    "numpy",
    "scipy",
    "pandas",
    "matplotlib",
    "seaborn",
    "nibabel",
    "nilearn",
    "pybids",
    "dipy",
    "networkx",
    "plotly",
    "tqdm",
    "h5py",
]

OPTIONAL = {
    "mechanics": ["dolfinx", "petsc4py", "basix", "ufl"],
    "modeling": ["tvb"],
    "registration": ["antspyx", "pydicom"],
    "visualization": ["pyvista", "vtk"],
    "ml": ["torch", "sklearn"],
    "dev": ["pytest", "black", "ruff"],
}


def check_package(name):
    """Check if a package is available."""
    spec = find_spec(name)
    return spec is not None


def get_version(name):
    """Get package version if available."""
    try:
        if name == "dolfinx":
            import dolfinx
            return dolfinx.__version__
        elif name == "petsc4py":
            import petsc4py
            return petsc4py.__version__
        elif name == "tvb":
            import tvb
            return tvb.__version__
        else:
            mod = __import__(name)
            return getattr(mod, "__version__", "unknown")
    except Exception:
        return "unknown"


def print_header():
    """Print header information."""
    print("\n" + "=" * 70)
    print("Finse 2026 Environment Checker")
    print("=" * 70)
    print(f"Python: {sys.version}")
    print(f"Platform: {platform.platform()}")
    print(f"Architecture: {platform.machine()}")
    print()


def check_required():
    """Check required packages."""
    print("Required Packages:")
    print("-" * 70)
    
    missing = []
    for name in REQUIRED:
        available = check_package(name)
        status = "✓" if available else "✗"
        version = get_version(name) if available else "N/A"
        print(f"  {status} {name:<20} {version}")
        if not available:
            missing.append(name)
    
    print()
    return missing


def check_optional():
    """Check optional packages."""
    print("Optional Packages:")
    print("-" * 70)
    
    for group, packages in OPTIONAL.items():
        print(f"  {group.upper()}:")
        for name in packages:
            available = check_package(name)
            status = "✓" if available else "✗"
            version = get_version(name) if available else "N/A"
            print(f"    {status} {name:<18} {version}")
    print()


def main():
    """Run environment check."""
    print_header()
    
    missing = check_required()
    check_optional()
    
    if missing:
        print(f"Missing {len(missing)} required package(s):")
        for name in missing:
            print(f"  - {name}")
        
        print("\nInstall with:")
        print(f"  pip install {' '.join(missing)}")
        print("\nOr create environment with:")
        print("  pip install -e .")
        return 1
    else:
        print("All required packages available!")
        print("\nTo install optional dependencies:")
        print("  pip install -e '.[all]'          # install everything")
        print("  pip install -e '.[mechanics]'    # for FEM simulations")
        print("  pip install -e '.[modeling]'     # for whole-brain models")
        print("  pip install -e '.[dev]'          # for development")
        return 0


if __name__ == "__main__":
    sys.exit(main())

