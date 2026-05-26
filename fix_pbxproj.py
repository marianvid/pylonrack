p = open('/Volumes/Marian_Backup/work/pylonrack/PylonRack/PylonRack.xcodeproj/project.pbxproj', 'r', encoding='utf-8')
content = p.read()
p.close()

lines = content.split('\n')
new_lines = []
skip_ids = {'BB000009', 'BB000010', 'BB000011', 'BB100009', 'BB100010', 'BB100011'}
for line in lines:
    stripped = line.strip()
    skip = False
    for sid in skip_ids:
        if stripped.startswith(sid + ' ') or stripped.startswith(sid + '='):
            skip = True
            break
    if skip:
        print("Removing:", stripped[:60])
        continue
    new_lines.append(line)

for i, line in enumerate(new_lines):
    if 'BB100001' in line and 'children' in line:
        new_lines[i] = '\t\t\tchildren = (BB100001, BB100008, BB100013, BB100014,);'
        print("Fixed children:", new_lines[i].strip())
        break

for i, line in enumerate(new_lines):
    if 'BB000005, BB000006, BB000007' in line:
        new_lines[i] = '\t\t\t\tBB000005, BB000006, BB000007, BB000013, BB000014,'
        print("Fixed sources:", new_lines[i].strip())
        break

for i, line in enumerate(new_lines):
    if line.strip() == 'BB000011,':
        new_lines[i] = ''
        print("Removed dangling BB000011")
        break

open('/Volumes/Marian_Backup/work/pylonrack/PylonRack/PylonRack.xcodeproj/project.pbxproj', 'w', encoding='utf-8').write('\n'.join(new_lines))
print("Done")
