"""
Adds shared app sources to test target build phase.
These are needed because BUNDLE_LOADER doesn't expose symbols reliably for Swift @MainActor types.
"""
from pathlib import Path

p = Path("/Volumes/Marian_Backup/work/pylonrack/PylonRack/PylonRack.xcodeproj/project.pbxproj")
content = p.read_text(encoding="utf-8")

# Map of new PBXBuildFile ID -> existing PBXFileReference ID for shared sources
# We create new build file entries that reference the same file refs as app sources
shared = [
    ("BS0001", "AA1006", "Slot.swift"),
    ("BS0002", "AA1007", "SlotStatus.swift"),
    ("BS0003", "AA1008", "SlotManifest.swift"),
    ("BS0004", "AA1009", "SlotConnection.swift"),
    ("BS0005", "AA1010", "SlotProcess.swift"),
    ("BS0006", "AA1012", "RackController.swift"),
    ("BS0007", "AA1013", "RackFolderDelegate.swift"),
    ("BS0008", "AA1016", "LocalSlotConfig.swift"),
    ("BS0009", "AA1017", "PortFinder.swift"),
    ("BS0010", "AA1003", "SettingsStore.swift"),
    ("BS0011", "AA1004", "SystemEnvironment.swift"),
]

# Add PBXBuildFile entries
bf_entries = "\n".join(f"\t\t{bf} = {{isa = PBXBuildFile; fileRef = {fr}; }};" for bf, fr, _ in shared)
content = content.replace(
    "/* End PBXBuildFile section */",
    bf_entries + "\n/* End PBXBuildFile section */"
)

# Add to BB_SRC sources build phase
shared_bfs = ", ".join(bf for bf, _, _ in shared)
content = content.replace(
    "BB_SRC = { isa = PBXSourcesBuildPhase;",
    f"BB_SRC = {{ isa = PBXSourcesBuildPhase;"
)

# Find and update the BB_SRC files list
test_sources_line = None
for line in content.split('\n'):
    if 'BB_SRC' in line and 'PBXSourcesBuildPhase' in line:
        test_sources_line = line
        break

# The BB_SRC line looks like:
# BB_SRC = { isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (BB0001, BB0002, ...); runOnly... };
old_bbs = "BB_SRC = { isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (BB0001, BB0002, BB0003, BB0004, BB0005, BB0006, BB0007,); runOnlyForDeploymentPostprocessing = 0; };"
new_bbs = f"BB_SRC = {{ isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (BB0001, BB0002, BB0003, BB0004, BB0005, BB0006, BB0007, {shared_bfs},); runOnlyForDeploymentPostprocessing = 0; }};"

if old_bbs in content:
    content = content.replace(old_bbs, new_bbs)
    print("Updated BB_SRC")
else:
    print("ERROR: BB_SRC line not found exactly")
    # Try to find it
    for line in content.split('\n'):
        if 'BB_SRC' in line:
            print("Found:", repr(line[:120]))

p.write_text(content, encoding="utf-8")
print("Done")
