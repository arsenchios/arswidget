"""Compile an isolated AppKit harness with actual production positioning methods."""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]


def method(path, signature):
    source = (root / path).read_text()
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


adjust = method("ArsWidget/ArsWidgetApp.swift", "@objc func adjustWindowPosition(")
if "--old-geometry" in sys.argv:
    adjust = adjust.replace(
        "vm.refreshScreenGeometry(for: selectedScreen.displayUUID)",
        "vm.screenUUID = selectedScreen.displayUUID\n"
        "vm.notchSize = getClosedNotchSize(screenUUID: selectedScreen.displayUUID)",
    )
refresh = method("ArsWidget/models/ArsWidgetViewModel.swift", "func refreshScreenGeometry(")
stubs = (root / "tests/VocabPromptLayoutTests.swift").read_text().split("private struct PromptLayoutHarness:")[0]
fixture = (root / "tests/VocabScreenGeometryTests.swift").read_text()
fixture = fixture.replace("// __PRODUCTION_REFRESH__", refresh).replace("// __PRODUCTION_ADJUST__", adjust)
with tempfile.TemporaryDirectory(prefix="arswidget-screen-geometry-") as directory:
    source = Path(directory) / "Fixture.swift"
    binary = Path(directory) / "screen-geometry-tests"
    source.write_text(stubs + fixture)
    subprocess.run([
        "swiftc", "-module-cache-path", "/private/tmp/arswidget-tests-module-cache",
        str(source), str(root / "ArsWidget/components/Vocab/VocabPromptCardView.swift"),
        str(root / "ArsWidget/components/Notch/NotchShape.swift"), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True)
