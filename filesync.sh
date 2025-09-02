if [[ "$1" == "--make" ]]; then
    target="filesync"

    # Detect shell
    shell_name=$(basename "$SHELL")

    # Candidate install paths
    candidate_paths=( "$HOME/bin" "$HOME/.local/bin" "/usr/local/bin" )

    install_path=""

    for path in "${candidate_paths[@]}"; do
        if [[ ":$PATH:" == *":$path:"* ]]; then
            install_path="$path"
            break
        fi
    done

	if [[ -n "$install_path" ]]; then
		mkdir -p "$install_path"
		cp "$0" "$install_path/$target"
		chmod +x "$install_path/$target"
		if [[ "$1" != "--silent" || "$1" != "-s" ]]; then
			echo "Installed $target into $install_path (detected shell: $shell_name)"
			echo "You can now run: $target"
		fi
    else
        cp "$0" "$target"
        chmod +x "$target"
	if [[ "$1" != "--silent" || "$1" != "-s" ]]; then
		echo "Created $target in current directory (detected shell: $shell_name)"
		echo "But no suitable PATH directory was found."
		echo "Run with ./filesync or move it manually into a PATH dir."
	fi
    fi
    exit 0
fi

if [[ "$1" == "--removecommand" ]]; then
    target="filesync"
    candidate_paths=( "$HOME/bin" "$HOME/.local/bin" "/usr/local/bin" )

    removed=false
    for path in "${candidate_paths[@]}"; do
        if [[ -x "$path/$target" ]]; then
            rm -f "$path/$target"
		if [[ "$1" != "--silent" || "$1" != "-s" ]]; then
			echo "Removed $target from $path"
		fi
		removed=true
        fi
    done

    if [[ "$removed" = false ]]; then
        echo "No installed $target command found in PATH directories."
    fi
    exit 0
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat <<EOF
Usage: $0 [OPTION] 
       $0 <dominant_path> <secondary_path>

Syntax:
  Options or Dominant path name, secondary path name

Options:
  --make             Create an executable copy of this script as 'filesync'
                     and install it into a directory on your PATH if possible.
  --removecommand    Remove the installed 'filesync' command from your PATH.
  -p, --preserve     Preserve files for testing or checking
  -h, --help         Show this help message and exit.
  -s, --silent       Does not provide any messages

Examples:
  $0 --make
  filesync
  $0 --removecommand
  $0 /source/path /destination/path -p
EOF
    exit 0
fi

dominant="$1"
secondary="$2"
preserve=0

# Parse optional preserve flag
for arg in "${@:3}"; do
    case "$arg" in
        -p|--preserve)
            preserve=1
            ;;
    esac
done

if [[ ! -d "$dominant" || ! -d "$secondary" ]]; then
	$0 -h
    exit 1
fi

dominant=$(cd "$dominant" && pwd)
secondary=$(cd "$secondary" && pwd)

temp_dom_files=$(mktemp)
temp_sec_files=$(mktemp)
temp_dom_dirs=$(mktemp)
temp_sec_dirs=$(mktemp)

updated=0
removed=0
created=0

cd "$dominant"
find . -type f | sed 's|^\./||' > "$temp_dom_files"
find . -type d | sed 's|^\./||' > "$temp_dom_dirs"
cd "$secondary"
find . -type f | sed 's|^\./||' > "$temp_sec_files"
find . -type d | sed 's|^\./||' > "$temp_sec_dirs"
cd - >/dev/null || exit 1

# Function to reverse lines portably (tac fallback)
reverse_lines() {
    if command -v tac >/dev/null 2>&1; then
        tac "$1"
    elif tail -r "$1" >/dev/null 2>&1; then
        tail -r "$1"
    else
        sed '1!G;h;$!d' "$1"
    fi
}

# Compare folders - create missing
while IFS= read -r dom_dir; do
    if ! grep -qxF "$dom_dir" "$temp_sec_dirs"; then
        echo "Missing folder: $dom_dir"
        ((created++))
        if [[ $preserve -eq 0 ]]; then
            mkdir -p "$secondary/$dom_dir"
        fi
    fi
done < "$temp_dom_dirs"

# Compare folders - remove extra (reverse order)
reverse_lines "$temp_sec_dirs" | while IFS= read -r sec_dir; do
    if ! grep -qxF "$sec_dir" "$temp_dom_dirs"; then
        echo "Extra folder: $sec_dir"
        ((removed++))
        if [[ $preserve -eq 0 ]]; then
            rm -rf "$secondary/$sec_dir"
        fi
    fi
done

# Compare files - update or create missing
while IFS= read -r dom_file; do
    dom_base="${dom_file%.*}"
    matched_file=""
    found_match=0

    while IFS= read -r sec_file; do
        sec_base="${sec_file%.*}"
        if [[ "$sec_base" == "$dom_base" ]]; then
            matched_file="$sec_file"
            found_match=1
            if ! cmp -s "$dominant/$dom_file" "$secondary/$sec_file"; then
                echo "Update file: $dom_file"
                ((updated++))
                if [[ $preserve -eq 0 ]]; then
                    cp "$dominant/$dom_file" "$secondary/$sec_file"
                fi
            fi
            break
        fi
    done < "$temp_sec_files"

    if [[ $found_match -eq 0 ]]; then
        echo "Missing file: $dom_file"
        ((created++))
        if [[ $preserve -eq 0 ]]; then
            mkdir -p "$(dirname "$secondary/$dom_file")"
            cp "$dominant/$dom_file" "$secondary/$dom_file"
        fi
    fi
done < "$temp_dom_files"

# Compare files - remove extra
while IFS= read -r sec_file; do
    sec_base="${sec_file%.*}"
    matched=0

    while IFS= read -r dom_file; do
        dom_base="${dom_file%.*}"
        if [[ "$dom_base" == "$sec_base" ]]; then
            matched=1
            break
        fi
    done < "$temp_dom_files"

    if [[ $matched -eq 0 ]]; then
        echo "Extra file: $sec_file"
        ((removed++))
        if [[ $preserve -eq 0 ]]; then
            rm -f "$secondary/$sec_file"
        fi
    fi
done < "$temp_sec_files"

rm -f "$temp_dom_files" "$temp_sec_files" "$temp_dom_dirs" "$temp_sec_dirs"

echo
echo "Summary"
echo "Updated $updated file(s)/folder(s)"
echo "Removed $removed file(s)/folder(s)"
echo "Created $created file(s)/folder(s)"
echo

if [[ $preserve -eq 1 ]]; then
    echo "Dry-run complete. No changes were made."
else
    echo "Sync complete. '$secondary' now matches '$dominant'."
fi
