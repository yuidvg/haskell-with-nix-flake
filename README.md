# haskell-with-nix-flake
Haskell Development Environment with Nix, Using haskell-flake.

# External Dependency
## Prerequisites
- flake-enabled nix
  - installed flake-enabled nix can be achieved via devcontainer

##  Confortable VSCode Environment
- `direnv allow` on project root
- Extensions
  - haskell.haskell
  - justusadam.language-haskell
  - hoovercj.haskell-linter
  - gattytto.phoityne-vscode
  - pinage404.nix-extension-pack
  - github.vscode-github-actions
  - usernamehw.errorlens
  - tomoki1207.pdf

# Testing

## Test Environment

The testing environment is managed through Nix flakes, providing:
- **Ultimate Reproducibility**: Complete environment definition (OS, libraries, specific versions of tools, test files)
- **Automatic Dependency Management**: Both system tools and custom programs are managed by Nix
- **CI/CD Integration**: Tests can be run consistently across different environments

## Test Structure

### 1. E2E Test (`test/e2e-test.sh`)

## Running Tests

### Using Nix (Recommended)
```bash
# Run all tests
nix flake check

# Run individual tests
nix build .#checks.aarch64-darwin.e2e-test
```

### Manual Testing in Development Environment
```bash
# Enter development shell
nix develop

# Build the project
cabal build

# Run tests manually
./test/e2e-test.sh
./test/hotp-test.sh
```

## Test Implementation Details

The tests are implemented following functional programming and Test-Driven Development (TDD) principles:

1. **Separation of Concerns**: Test logic is separated into dedicated shell scripts, while Nix configuration handles environment setup
2. **Reusability**: Helper functions (`mkTestScript`) reduce duplication in test definitions
3. **Error Handling**: Comprehensive error checking for missing dependencies and files
4. **Path Resolution**: Robust path handling for different execution contexts

## TDD Workflow

The testing framework supports the Red-Green-Refactor cycle:
- **Red**: Tests fail when implementation doesn't match oathtool behavior
- **Green**: Implementation is corrected to pass tests
- **Refactor**: Code is improved while maintaining test compatibility

## Test Configuration

Tests are defined in `flake.nix` using the `mkTestScript` helper function:

```nix
checks.e2e-test = mkTestScript
  "<project-name>-e2e-test"
  "test/e2e-test.sh"
  [ self'.packages.<project-name> pkgs.oathToolkit ];
```

This approach ensures that:
- Tests are reproducible across environments
- Dependencies are automatically managed
- Test results are consistent and reliable
