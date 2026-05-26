p = open('/Volumes/Marian_Backup/work/pylonrack/PylonRack/PylonRack.xcodeproj/project.pbxproj', 'r', encoding='utf-8')
content = p.read()
p.close()

# Add PBXBuildFile entries
content = content.replace(
    'BB000012 = {isa = PBXBuildFile; fileRef = BB100012; };',
    'BB000012 = {isa = PBXBuildFile; fileRef = BB100012; };\n\t\tBB000013 = {isa = PBXBuildFile; fileRef = BB100013; };\n\t\tBB000014 = {isa = PBXBuildFile; fileRef = BB100014; };'
)

# Add PBXFileReference entries
content = content.replace(
    'BB100012 = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = Network.framework; path = System/Library/Frameworks/Network.framework; sourceTree = SDKROOT; };',
    'BB100012 = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = Network.framework; path = System/Library/Frameworks/Network.framework; sourceTree = SDKROOT; };\n\t\tBB100013 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SlotConnectionTests.swift; sourceTree = "<group>"; };\n\t\tBB100014 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RackControllerTests.swift; sourceTree = "<group>"; };'
)

# Add to sources build phase
content = content.replace(
    'BB000005, BB000006, BB000007, BB000013, BB000014,',
    'BB000005, BB000006, BB000007,'
)
# Now add them properly
content = content.replace(
    'BB000005, BB000006, BB000007,\n\t\t\t);',
    'BB000005, BB000006, BB000007, BB000013, BB000014,\n\t\t\t);'
)

open('/Volumes/Marian_Backup/work/pylonrack/PylonRack/PylonRack.xcodeproj/project.pbxproj', 'w', encoding='utf-8').write(content)
print("Done")
print("BB100013 present:", 'BB100013' in content)
print("BB100014 present:", 'BB100014' in content)
print("BB000013 in sources:", 'BB000013' in content)
