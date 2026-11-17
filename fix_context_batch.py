#!/usr/bin/env python3
"""
Automatically add `if (!context.mounted) return;` checks after async operations
"""
import re
import sys
from pathlib import Path

def fix_context_safety(file_path):
    """Add mounted checks after await statements that use context"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return 0
    
    changes = 0
    i = 0
    while i < len(lines):
        line = lines[i]
        
        # Check if line uses context in problematic ways
        if any(pattern in line for pattern in [
            'Navigator.',
            'showDialog',
            'showModalBottomSheet',
            'showBottomSheet',
            'ScaffoldMessenger.of(context)',
            'Theme.of(context)',
        ]):
            # Look backwards to find most recent await
            j = i - 1
            found_await = False
            found_mounted_check = False
            
            while j >= 0 and (i - j) < 50:
                prev_line = lines[j]
                
                # Check if there's already a mounted check
                if re.search(r'if\s*\(\s*!.*context\.mounted.*\)', prev_line):
                    found_mounted_check = True
                    break
                    
                # Check if there's an await
                if 'await ' in prev_line:
                    found_await = True
                    break
                    
                # Stop if we hit a function boundary
                if re.match(r'^\s*(Future<|void |bool |String |int |double |\w+\s+\w+\s*\()', prev_line):
                    break
                    
                j -= 1
            
            # If we found await but no mounted check, add one
            if found_await and not found_mounted_check:
                # Calculate indentation from current line
                indent_match = re.match(r'^(\s*)', line)
                indent = indent_match.group(1) if indent_match else ''
                
                # Insert mounted check before current line
                lines.insert(i, f'{indent}if (!context.mounted) return;\n')
                changes += 1
                i += 1  # Skip the line we just inserted
        
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
        print("Usage: python fix_context_batch.py <file1> <file2> ...")
        sys.exit(1)
    
    total_changes = 0
    for file_path in sys.argv[1:]:
        path = Path(file_path)
        if path.exists() and path.suffix == '.dart':
            changes = fix_context_safety(path)
            total_changes += changes
        else:
            print(f"Skipping {file_path} (not found or not a .dart file)")
    
    print(f"\n📊 Total changes: {total_changes}")
    return total_changes

if __name__ == '__main__':
    main()
