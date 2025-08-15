# Build System Overview

This document describes the comprehensive build system for CloudyPad, including workflows, Docker images, tests, and deployment processes.

## Build Infrastructure

CloudyPad uses a multi-layered build system with the following components:

### GitHub Actions Workflows

Located in `.github/workflows/`, these workflows handle automated building, testing, and deployment:

#### Core Workflows

1. **`test-unit.yml`** - Unit Testing and Core Builds
   - Runs on every push and PR
   - Executes 127+ unit tests
   - Builds TypeScript code
   - Tests installation scripts on Ubuntu and macOS
   - Builds and validates Docker images
   - Validates TypeScript compilation

2. **`test-integ.yml`** - Integration Testing
   - Runs integration tests that don't require external accounts
   - Tests S3 backend functionality with local MinIO
   - Tests dummy provider functionality
   - Validates core infrastructure components

3. **`release.yml`** - Release and Docker Publishing
   - Triggered on git tags
   - Builds multi-architecture Docker images (amd64/arm64)
   - Publishes to GitHub Container Registry
   - Handles both core and sunshine container images

4. **`doc.yml`** - Documentation Deployment
   - Builds mdBook documentation
   - Deploys to GitHub Pages
   - Automatic deployment on master branch

5. **`validate.yml`** - Quality Assurance
   - Validates workflow syntax
   - Checks documentation completeness
   - Runs code quality checks
   - Validates TypeScript compilation
   - Tests Docker configuration validity

### Task Runner (Taskfile.yml)

CloudyPad uses [Task](https://taskfile.dev/) as the primary build tool. Key tasks include:

#### Testing Tasks
- `test-unit` - Run all unit tests
- `test-integ-*` - Various integration test suites
- `test-compile` - TypeScript compilation check
- `test-docker-build-config` - Validate Docker configurations

#### Build Tasks
- `build-npm` - Build TypeScript to JavaScript
- `build-core-container-*` - Build core CloudyPad Docker image
- `build-sunshine-container-*` - Build Sunshine streaming server image

#### Quality Tasks
- `test-circular-deps` - Detect circular dependencies
- `test-analytics-key-match` - Validate analytics configuration consistency

## Docker Build System

### Multi-Stage Builds

CloudyPad uses sophisticated multi-stage Docker builds for optimization:

#### Core Image (`Dockerfile`)
1. **Build Stage** - Base Node.js environment with build tools
2. **Pulumi Stage** - Downloads and installs Pulumi CLI
3. **TypeScript Stage** - Compiles TypeScript code
4. **Final Stage** - Production-ready image with compiled code

#### Sunshine Image (`containers/sunshine/Dockerfile`)
1. **Download Stages** - Parallel download of gaming components
2. **Base Stage** - Ubuntu with desktop environment
3. **Final Stage** - Gaming-ready container with Sunshine streaming

### Build Variants

- **Local**: `task build-*-container-local` - Fast local development
- **CI**: `task build-*-container-ci` - CI/CD with caching
- **Release**: `task build-*-container-release` - Multi-arch production builds

## Testing Strategy

### Three-Tier Testing

1. **Unit Tests** (127 tests)
   - Fast, isolated component testing
   - No external dependencies
   - 100% TypeScript coverage of core logic

2. **Integration Tests** 
   - Tests component interaction
   - Uses local services (MinIO for S3 testing)
   - Provider-specific testing with dummy provider

3. **End-to-End Tests**
   - Full lifecycle testing (manual for now)
   - Real cloud provider testing
   - Installation and deployment validation

### Test Infrastructure

- **Mocha** - Test framework
- **Docker Compose** - Integration test services
- **Temporary File System** - Isolated test environments
- **Sinon** - Mocking and stubbing

## Continuous Integration

### Build Matrix

- **Platforms**: Ubuntu 22.04, Ubuntu 24.04, macOS 13, macOS 14
- **Node.js**: Version 22.13.1 (specified in Dockerfile)
- **Architectures**: amd64, arm64 (for Docker builds)

### Caching Strategy

- **Nix Cache** - Development environment caching
- **NPM Cache** - Node.js dependency caching  
- **Docker Layer Cache** - Multi-stage build optimization
- **Registry Cache** - Docker image layer sharing

## Development Workflow

### Local Development

1. **Setup**: Use Nix development shell (`nix develop`)
2. **Build**: `task build-npm`
3. **Test**: `task test-unit`
4. **Docker**: `task build-core-container-local`

### Quality Checks

Before committing, run:
```bash
task test-unit
task test-compile
task test-circular-deps
task test-docker-build-config
```

### Release Process

1. **Pre-release**: Run `task test-integ-full-lifecycle-all` manually
2. **Create Release**: `task release-create`
3. **Automated**: GitHub Actions handles Docker builds and publishing

## Deployment

### Documentation
- **Source**: `docs/src/` (Markdown)
- **Build**: mdBook generates static site
- **Deploy**: GitHub Pages automatic deployment

### Container Images
- **Registry**: GitHub Container Registry (ghcr.io)
- **Tags**: Version-based and environment-based
- **Base Images**: 
  - Core: `ghcr.io/ap0ught/cloudypad:VERSION`
  - Sunshine: `ghcr.io/ap0ught/cloudypad/sunshine:VERSION`

### Installation
- **Script**: `install.sh` for cross-platform installation
- **Package**: `cloudypad.sh` launcher script
- **Container**: Docker/Podman compatible

## Monitoring and Validation

### Build Status
All builds include comprehensive validation:
- Syntax checking
- Dependency validation
- Security scanning
- Performance testing

### Quality Gates
- All unit tests must pass
- TypeScript compilation must succeed
- Docker configurations must be valid
- Documentation must build successfully

## Troubleshooting

### Common Issues

1. **Network Dependencies**: Docker builds require internet access for downloading dependencies
2. **Nix Environment**: Some tasks require Nix development environment
3. **External Accounts**: Full integration tests require cloud provider accounts

### Debug Commands

```bash
# Check build status
task test-compile

# Validate configurations
task test-docker-build-config

# Test core functionality
task test-unit

# Debug specific component
npx mocha test/unit/specific/test.spec.ts
```

## Performance Optimization

### Build Speed
- Multi-stage Docker builds minimize layer size
- NPM ci for faster dependency installation
- Parallel build stages where possible

### Cache Utilization
- Local file system cache for development
- Registry-based cache for CI/CD
- Incremental builds for faster iteration

### Resource Management
- Temporary file cleanup
- Memory-efficient test isolation
- Optimized container layer ordering

This build system ensures reliable, fast, and maintainable development and deployment processes for CloudyPad.