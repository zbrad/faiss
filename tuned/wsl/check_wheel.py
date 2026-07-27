#!/usr/bin/env python3
"""Quick wheel content inspector.

Usage: python3 check_wheel.py [dir]
Defaults to <repo_root>/build_output_rtx40, where repo_root is inferred from
this script's own location (not a hardcoded drive-letter guess). Pass
build_output_rtx50 for the other build.
"""
import zipfile, sys, pathlib

_repo_root = pathlib.Path(__file__).resolve().parents[2]  # wsl/ -> tuned/ -> repo root
whl_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else str(_repo_root / "build_output_rtx40"))
wheels = list(whl_dir.glob("*.whl"))
if not wheels:
    print("No wheel found in", whl_dir)
    sys.exit(1)

for whl in wheels:
    print(f"\nWheel: {whl.name}  ({whl.stat().st_size/1024/1024:.1f} MB)")
    with zipfile.ZipFile(whl) as z:
        members = z.namelist()
        so_files = [n for n in members if n.endswith(".so")]
        print(f"  Total entries : {len(members)}")
        print(f"  .so files ({len(so_files)}):")
        for f in so_files:
            info = z.getinfo(f)
            print(f"    {info.compress_size/1024:6.0f} kB  {f}")
