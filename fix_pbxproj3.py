p = open('/Volumes/Marian_Backup/work/pylonrack/PylonRack/PylonRack.xcodeproj/project.pbxproj', 'r', encoding='utf-8')
content = p.read()
p.close()

# Remove the bad AA entries from BB sources
content = content.replace(
    '\t\t\t\tBB000001, BB000008, BB000002, BB000003, BB000004,\n\t\t\t\tBB000005, BB000006, BB000007, BB000013, BB000014,\n\t\t\t\tAA000008, AA000011, AA000009,',
    '\t\t\t\tBB000001, BB000008, BB000002, BB000003, BB000004,\n\t\t\t\tBB000005, BB000006, BB000007, BB000013, BB000014,\n\t\t\t\tBB000015, BB000016, BB000017,'
)

# Add new PBXBuildFile entries (BB000015=SlotConnection, BB000016=RackController, BB000017=SlotProcess from app sources)
content = content.replace(
    'BB000013 = {isa = PBXBuildFile; fileRef = BB100013; };\n\t\tBB000014 = {isa = PBXBuildFile; fileRef = BB100014; };',
    'BB000013 = {isa = PBXBuildFile; fileRef = BB100013; };\n\t\tBB000014 = {isa = PBXBuildFile; fileRef = BB100014; };\n\t\tBB000015 = {isa = PBXBuildFile; fileRef = AA100008; };\n\t\tBB000016 = {isa = PBXBuildFile; fileRef = AA100011; };\n\t\tBB000017 = {isa = PBXBuildFile; fileRef = AA100009; };'
)

open('/Volumes/Marian_Backup/work/pylonrack/PylonRack/PylonRack.xcodeproj/project.pbxproj', 'w', encoding='utf-8').write(content)
print("Done")
print("BB000015 present:", 'BB000015' in content)
print("BB000016 present:", 'BB000016' in content)
