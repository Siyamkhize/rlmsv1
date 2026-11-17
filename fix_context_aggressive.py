#!/usr/bin/env python3
"""
Aggressive context safety fixer - finds ALL context usages after ANY await
"""
import re
import sys
from pathlib import Path

def fix_file_aggressive(file_path):
    """Aggressively add mounted checks before every context usage after await"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return 0
    
    changes = 0
    
    # Context usage patterns (more comprehensive)
    context_patterns = [
        (r'Navigator\.', 'Navigator'),
        (r'showDialog\s*\(', 'showDialog'),
        (r'showModalBottomSheet\s*\(', 'showModalBottomSheet'),
        (r'showBottomSheet\s*\(', 'showBottomSheet'),
        (r'ScaffoldMessenger\.of\s*\(\s*context\s*\)', 'ScaffoldMessenger'),
        (r'Theme\.of\s*\(\s*context\s*\)', 'Theme.of'),
        (r'MediaQuery\.of\s*\(\s*context\s*\)', 'MediaQuery.of'),
        (r'FocusScope\.of\s*\(\s*context\s*\)', 'FocusScope.of'),
    ]
    
    i = 0
    while i < len(lines):
        line = lines[i]
        
        # Check if line contains context usage
        for pattern, name in context_patterns:
            if re.search(pattern, line):
                # Check if line already has inline mounted check or is after one
                if i > 0 and re.search(r'if\s*\(\s*!.*context\.mounted.*\)', lines[i-1]):
                    break  # Already has check
                if re.search(r'if\s*\(\s*!.*context\.mounted.*\)', line):
                    break  # Has inline check
                
                # Look backwards for await (within 100 lines)
                found_await = False
                for j in range(max(0, i-100), i):
                    if re.search(r'\bawait\s', lines[j]):
                        found_await = True
                        break
                    # Stop at function boundaries
                    if j < i - 5 and re.match(r'^\s*(@override|Widget |Future |void |class )', lines[j]):
                        break
                
                if found_await:
                    # Get indentation
                    indent_match = re.match(r'^(\s*)', line)
                    indent = indent_match.group(1) if indent_match else '      '
                    
                    # Insert mounted check
                    lines.insert(i, f'{indent}if (!context.mounted) return;\n')
                    changes += 1
                    i += 1  # Skip inserted line
                    break  # Only add one check per line
        
        i += 1
    
    if changes > 0:
        try:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.writelines(lines)
            print(f"✅ Fixed {changes} issues in {file_path}")
        except Exception as e:
            print(f"Error writing {file_path}: {e}")
            return 0
    
    return changes

def main():
    if len(sys.argv) < 2:
        print("Usage: python fix_context_aggressive.py <file1> <file2> ...")
        sys.exit(1)
    
    total_changes = 0
    for file_path in sys.argv[1:]:
        path = Path(file_path)
        if path.exists() and path.suffix == '.dart':
            changes = fix_file_aggressive(path)
            total_changes += changes
        else:
            print(f"Skipping {file_path}")
    
    print(f"\n📊 Total changes: {total_changes}")
    return total_changes

if __name__ == '__main__':
    main()
