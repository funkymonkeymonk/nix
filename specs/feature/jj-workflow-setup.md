# JJ Workflow Setup Specification

## Overview

This specification outlines the implementation of Jujutsu (JJ) as a Git-compatible VCS to enhance the development workflow while maintaining strict safety and oversight requirements for AI-assisted development.

## Current State

### Existing Workflow
- **Version Control**: Git with GitHub as remote repository
- **Automation**: Task-based workflow using go-task (Taskfile.yml)
- **CI/CD**: GitHub Actions with matrix testing (x86_64-linux, aarch64-darwin)
- **Development Environment**: Devenv with pre-commit hooks (alejandra, deadnix, yamllint)
- **Security**: 1Password SSH commit signing, AI assistant constraints (AGENTS.md)

### AI Assistant Constraints (AGENTS.md)
- Cannot make autonomous commits without explicit user approval
- Cannot push changes without explicit user review
- Must maintain human oversight for all critical operations

## Proposed Changes

### 1. JJ Integration
- Add JJ to development environment (devenv.nix)
- Install JJ package for all developers
- Maintain Git compatibility for CI/CD and GitHub integration

### 2. Anonymous Branch Workflow
Implement JJ's anonymous branches to enable AI-assisted development while maintaining human oversight:

#### AI Preparation Phase
- AI creates anonymous branches for changes
- AI can modify files and commit to anonymous branches
- No direct commits to main branch or remote repository

#### Human Review Phase
- User reviews anonymous branches using JJ commands
- User inspects changes with `jj diff` and `jj show`
- User reviews operation log with `jj op log`

#### Integration Phase
- User explicitly merges approved anonymous branches to main
- User creates final commit messages
- User manually pushes changes to remote

### 3. Taskfile.yml Enhancements
Add new tasks for JJ workflow management:

```yaml
# AI preparation tasks
ai:prepare-branch    # Create anonymous branch
ai:commit-changes    # Commit to anonymous branch
ai:status           # Show JJ status

# User review tasks
review:branches     # Show all branches
review:changes      # Show changes in branch
review:operations   # Show operation log

# Integration tasks
integrate:branch    # Merge anonymous branch to main
finalize:commit     # Create final commit

# Workflow orchestration
workflow:ai-review  # Complete review workflow
workflow:ai-complete # Complete integration workflow
```

### 4. Development Environment Updates
Add JJ to devenv.nix packages list for consistent tooling across all developers.

## Implementation Plan

### Phase 1: Environment Setup
1. Add JJ to devenv.nix
2. Test JJ installation in development environment
3. Verify GitHub Actions compatibility

### Phase 2: Task Implementation
1. Add JJ workflow tasks to Taskfile.yml
2. Test task functionality
3. Update documentation

### Phase 3: Workflow Documentation
1. Update README.md with JJ workflow instructions
2. Create JJ-specific documentation
3. Update AGENTS.md if needed

### Phase 4: Migration and Training
1. Parallel usage period (JJ locally, Git for CI/CD)
2. Team training on JJ workflows
3. Gradual adoption of JJ features

## Benefits

### For AI-Assisted Development
- **Enhanced Safety**: Anonymous branches prevent autonomous commits to main
- **Better Audit Trail**: JJ operation log provides detailed history
- **Flexible Review**: Users can modify/reject AI changes before integration

### For Development Workflow
- **Superior Conflict Resolution**: JJ's first-class conflicts vs Git's textual diffs
- **Automatic Snapshots**: Working copy always committed, no "dirty state" issues
- **Powerful History Rewriting**: Better tools for complex refactoring
- **Git Compatibility**: Seamless integration with existing GitHub workflows

### For Code Quality
- **Operation Tracking**: Every command logged for debugging
- **Undo Capability**: Easy reversal of operations
- **Concurrent Safety**: Repository remains consistent under concurrent operations

## Safety Considerations

### AI Assistant Constraints Compliance
- **No Autonomous Commits**: AI only works on anonymous branches
- **Human Approval Required**: All integration requires explicit user commands
- **Audit Trail**: JJ operation log provides complete traceability

### Security Maintenance
- **SSH Signing**: 1Password SSH signing continues to work
- **GitHub Integration**: CI/CD pipelines remain functional
- **Access Controls**: Existing permission models unchanged

### Risk Mitigation
- **Gradual Adoption**: Parallel usage prevents disruption
- **Fallback Available**: Git commands always available
- **Testing Required**: Comprehensive testing before full adoption

## Migration Strategy

### Phase 1: Tool Installation (Week 1)
- Add JJ to devenv.nix
- Update development environment
- Test basic JJ functionality

### Phase 2: Workflow Development (Week 2)
- Implement Taskfile.yml tasks
- Test AI assistant workflow
- Document new processes

### Phase 3: Parallel Usage (Weeks 3-4)
- Use JJ for local development
- Keep Git for CI/CD and critical operations
- Train team on JJ workflows

### Phase 4: Full Adoption (Week 5+)
- Switch primary workflow to JJ
- Update CI/CD if needed
- Monitor for issues

## Testing Plan

### Unit Testing
- Test JJ installation in devenv environment
- Verify Taskfile.yml tasks execute correctly
- Test anonymous branch creation/deletion

### Integration Testing
- Test AI assistant workflow end-to-end
- Verify GitHub Actions compatibility
- Test SSH signing with JJ commits

### User Acceptance Testing
- Team members test JJ workflows
- Validate safety constraints maintained
- Performance comparison with Git workflows

### Rollback Plan
- Git remains available as fallback
- Can revert to Git-only workflow if issues arise
- Documentation maintained for both tools

## Success Criteria

1. **Safety Maintained**: AI cannot make autonomous commits to main branches
2. **Workflow Improved**: Development tasks faster/more reliable with JJ
3. **Team Adoption**: All developers comfortable with JJ workflows
4. **CI/CD Unchanged**: GitHub Actions continue working without modification
5. **Documentation Complete**: All workflows documented and accessible

## Dependencies

- JJ package available in nixpkgs
- Team availability for training
- Testing time allocated
- Documentation review process

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| JJ tool instability | High | Parallel usage, easy rollback |
| Team learning curve | Medium | Comprehensive training, documentation |
| CI/CD compatibility | High | Thorough testing before adoption |
| AI workflow disruption | Medium | Maintain existing constraints, test thoroughly |

## Future Considerations

- JJ ecosystem maturity monitoring
- Advanced JJ features adoption (concurrent replication, etc.)
- Integration with other tools (GitHub CLI, etc.)
- Performance benchmarking vs Git workflows