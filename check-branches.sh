#!/bin/bash

# Script to check local branches for missing upstreams and prompt for action

set -e

# Get all local branches except the current one
current_branch=$(git rev-parse --abbrev-ref HEAD)
branches=$(git branch --format='%(refname:short)' | grep -v "^$current_branch$")

for branch in $branches; do
    # Check if branch has an upstream configured
    needs_action=false
    reason=""

    if git config branch."$branch".remote >/dev/null 2>&1; then
        # Has upstream configured, check if it exists on remote
        remote=$(git config branch."$branch".remote)
        merge=$(git config branch."$branch".merge)
        remote_branch=${merge#refs/heads/}

        if [ "$(git ls-remote --heads "$remote" "$remote_branch" | wc -l)" -eq 0 ]; then
            echo "Branch '$branch' upstream branch '$remote/$remote_branch' does not exist on remote."
            needs_action=true
        fi
    else
        # No upstream configured, check if remote branch exists at origin
        if [ "$(git ls-remote --heads origin "$branch" 2>/dev/null | wc -l)" -gt 0 ]; then
            echo "Branch '$branch' has no upstream configured, but remote branch exists. Setting upstream to origin/$branch."
            git branch --set-upstream-to=origin/"$branch" "$branch"
        else
            echo "Branch '$branch' has no upstream configured."
            needs_action=true
        fi
    fi

    if [ "$needs_action" = true ]; then
        echo "Options for branch '$branch':"
        echo "p. Push to origin (sets upstream if none)"
        echo "d. Delete branch"
        echo "k. Keep as is (default)"
        read -p "Choose (p/d/k) [k]: " choice
        if [ -z "$choice" ]; then
            choice=k
        fi

        case $choice in
            p)
                echo "Pushing '$branch' to origin..."
                git push -u origin "$branch"
                ;;
            d)
                echo "Deleting branch '$branch'..."
                git branch -D "$branch"
                ;;
            k)
                echo "Keeping branch '$branch' as is."
                ;;
            *)
                echo "Invalid choice, keeping branch '$branch' as is."
                ;;
        esac
        echo "---"
    fi
done

echo "Branch check complete."