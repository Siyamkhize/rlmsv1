#!/usr/bin/env python3
"""
Final comprehensive context safety fixer
Handles catch blocks, multiple awaits, and complex patterns
"""
import re
import sys
from pathlib import Path

def add_mounted_check_before_line(lines, line_idx, indent):
    """Add mounted check before the given line if not already present"""
    # Check if previous line already has mounted check
    if line_idx > 0:
        prev_line = lines[line_idx - 1]
        if re.search(r'if\s*\(\s*!.*context\.mounted.*\)', prev_line):
            return False
    
    # Check if current line already has inline check
    curr_line = lines[line_idx]
    if re.search(r'if\s*\(\s*!.*context\.mounted.*\)', curr_line):
        return False
    
    # Insert mounted check
    lines.insert(line_idx, f'{indent}if (!context.mounted) return;\n')
    return True

def fix_context_in_function(lines, func_start, func_end):
    """Fix all context issues within a function"""
    changes = 0
    i = func_start
    
    # Find all await statements in function
    await_lines = []
    for j in range(func_start, min(func_end, len(lines))):
        if re.search(r'\bawait\s', lines[j]):
            await_lines.append(j)
    
    if not await_lines:
        return 0
    
    # Context usage patterns
    context_patterns = [
        r'Navigator\.',
        r'showDialog\s*\(',
        r'showModalBottomSheet\s*\(',
        r'showBottomSheet\s*\(',
        r'ScaffoldMessenger\.of\s*\(\s*context\s*\)',
        r'Theme\.of\s*\(\s*context\s*\)',
        r'MediaQuery\.of\s*\(\s*context\s*\)',
    ]
    
    # Scan forward from each await to find context usage
    i = func_start
    while i < min(func_end, len(lines)):
        line = lines[i]
        
        # Check if this line uses context
        has_context = any(re.search(pattern, line) for pattern in context_patterns)
        
        if has_context:
            # Find most recent await before this line
            most_recent_await = -1
            for await_line in await_lines:
                if await_line < i:
                    most_recent_await = await_line
                else:
                    break
            
            if most_recent_await >= 0:
                # Check if there's a mounted check between await and context usage
                has_check = False
                for j in range(most_recent_await + 1, i):
                    if re.search(r'if\s*\(\s*!.*context\.mounted.*\)', lines[j]):
                        has_check = True
                        break
                
                if not has_check:
                    # Get indentation
                    indent_match = re.match(r'^(\s*)', line)
                    indent = indent_match.group(1) if indent_match else '      '
                    
                    # Add mounted check before this line
                    if add_mounted_check_before_line(lines, i, indent):
                        changes += 1
                        func_end += 1  # Adjust end since we inserted a line
                        i += 1  # Skip the line we just inserted
        
        i += 1
    
    return changes

def fix_context_safety_final(file_path):
    """Comprehensive context safety fixes"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
            lines = list(content.splitlines(keepends=True))
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return 0
    
    changes = 0
    i = 0
    
    # Find all async functions
    while i < len(lines):
        line = lines[i]
        
        # Detect async function start
        if re.search(r'^\s*(Future<|FutureOr<).*\basync\s*\{', line) or \
           (re.search(r'^\s*(Future<|FutureOr<|void\s+\w+.*\()', line) and 
            i + 1 < len(lines) and 'async' in lines[i + 1]):
            
            # Find function end (matching brace)
            func_start = i
            brace_count = 0
            func_end = i
            started = False
            
            for j in range(i, min(i + 1000, len(lines))):  # Limit search
                if '{' in lines[j]:
                    brace_count += lines[j].count('{')
                    started = True
                if '}' in lines[j]:
                    brace_count -= lines[j].count('}')
                if started and brace_count == 0:
                    func_end = j
                    break
            
            if func_end > func_start:
                func_changes = fix_context_in_function(lines, func_start, func_end)
                changes += func_changes
                i = func_end
        
        i += 1
    
    if changes > 0:
        try:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.writelines(lines)
            print(f"✅ Fixed {changes} issues in {file_path}")
        except Exception as e:
            print(f"Error writing {file_path}: {e}")
            return 0
    else:
        print(f"No changes needed in {file_path}")
    
    return changes

def main():
    if len(sys.argv) < 2:
        print("Usage: python fix_context_final.py <file1> <file2> ...")
        sys.exit(1)
    
    total_changes = 0
    for file_path in sys.argv[1:]:
        path = Path(file_path)
        if path.exists() and path.suffix == '.dart':
            changes = fix_context_safety_final(path)
            total_changes += changes
        else:
            print(f"Skipping {file_path} (not found or not a .dart file)")
    
    print(f"\n📊 Total changes: {total_changes}")
    return total_changes

if __name__ == '__main__':
    main()
