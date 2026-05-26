"""
Regenerează project.pbxproj cu PBXTargetDependency corect pentru @testable import.
"""
from pathlib import Path

# Re-read existing
p = Path("/Volumes/Marian_Backup/work/pylonrack/PylonRack/PylonRack.xcodeproj/project.pbxproj")
content = p.read_text(encoding="utf-8")

# Add PBXContainerItemProxy and PBXTargetDependency
proxy = """
/* Begin PBXContainerItemProxy section */
\t\tTGT_PROXY = {
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = PROJECT;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = AA_TGT;
\t\t\tremoteInfo = PylonRack;
\t\t};
/* End PBXContainerItemProxy section */
"""

dep = """
/* Begin PBXTargetDependency section */
\t\tTGT_DEP = {
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = AA_TGT;
\t\t\ttargetProxy = TGT_PROXY;
\t\t};
/* End PBXTargetDependency section */
"""

# Insert after PBXBuildFile section
content = content.replace(
    "/* Begin PBXFileReference section */",
    proxy.strip() + "\n\n/* Begin PBXFileReference section */"
)

# Insert after PBXGroup section
content = content.replace(
    "/* Begin PBXNativeTarget section */",
    dep.strip() + "\n\n/* Begin PBXNativeTarget section */"
)

# Add dependency to BB_TGT
content = content.replace(
    "\t\t\tdependencies = ();\n\t\t\tname = PylonRackTests;",
    "\t\t\tdependencies = (TGT_DEP,);\n\t\t\tname = PylonRackTests;"
)

p.write_text(content, encoding="utf-8")
print("Done")
