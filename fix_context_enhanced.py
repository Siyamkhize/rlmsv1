#!/usr/bin/env python3
"""
Enhanced context safety fixer - handles more complex patterns
"""
import re
import sys
from pathlib import Path

def fix_context_safety_enhanced(file_path):
    """Add mounted checks after await statements that use context"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
            lines = content.splitlines(keepends=True)
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return 0
    
    changes = 0
    i = 0
    
    # Patterns that indicate context usage
    context_patterns = [
        r'Navigator\.',
        r'showDialog\(',
        r'showModalBottomSheet\(',
        r'showBottomSheet\(',
        r'ScaffoldMessenger\.of\(context\)',
        r'Theme\.of\(context\)',
        r'MediaQuery\.of\(context\)',
        r'FocusScope\.of\(context\)',
        r'Scaffold\.of\(context\)',
    ]
    
    while i < len(lines):
        line = lines[i]
        
        # Check if line uses context in problematic ways
        has_context_usage = any(re.search(pattern, line) for pattern in context_patterns)
        
        if has_context_usage:
            # Look backwards to find most recent await
            j = i - 1
            found_await_line = -1
            found_mounted_check = False
            indent = ''
            
            # Get indent from current line
            indent_match = re.match(r'^(\s*)', line)
            if indent_match:
                indent = indent_match.group(1)
            
            while j >= 0 and (i - j) < 100:  # Increased lookback range
                prev_line = lines[j]
                
                # Check if there's already a mounted check between await and usage
                if re.search(r'if\s*\(\s*!.*context\.mounted.*\)', prev_line):
                    found_mounted_check = True
                    break
                
                # Check if there's an await on this line or lines above
                if re.search(r'\bawait\s', prev_line):
                    found_await_line = j
                    break
                
                # Stop at function/method boundaries
                if re.match(r'^\s*(Future<|void |bool |String |int |double |class |Widget |@override)', prev_line):
                    break
                    
                # Stop at opening braces that start a new scope
                if re.match(r'^\s*\{', prev_line) and j < i - 10:
                    break
                    
                j -= 1
            
            # If we found await but no mounted check, add one
            if found_await_line >= 0 and not found_mounted_check:
                # Find the right place to insert - after the await completes
                insert_line = found_await_line
                
                # If await is part of assignment or has continuation, find where it ends
                k = found_await_line
                while k < i:
                    if lines[k].rstrip().endswith(';'):
                        insert_line = k
                        break
                    k += 1
                
                # Insert after the await line
                insert_pos = insert_line + 1
                
                # Check if there's already a mounted check immediately after
                if insert_pos < len(lines):
                    next_line = lines[insert_pos]
                    if re.search(r'if\s*\(\s*!.*context\.mounted.*\)', next_line):
                        # Already has check, skip
                        i += 1
                        continue
                
                # Get the indent from the line after await
                if insert_pos < len(lines):
                    next_indent_match = re.match(r'^(\s*)', lines[insert_pos])
                    if next_indent_match:
                        indent = next_indent_match.group(1)
                
                # Insert mounted check
                lines.insert(insert_pos, f'{indent}if (!context.mounted) return;\n')
                changes += 1
                i += 1  # Account for inserted line
        
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
        print("Usage: python fix_context_enhanced.py <file1> <file2> ...")
        sys.exit(1)
    
    total_changes = 0
    for file_path in sys.argv[1:]:
        path = Path(file_path)
        if path.exists() and path.suffix == '.dart':
            changes = fix_context_safety_enhanced(path)
            total_changes += changes
        else:
            print(f"Skipping {file_path} (not found or not a .dart file)")
    
    print(f"\n📊 Total changes: {total_changes}")
    return total_changes

if __name__ == '__main__':
    main()
