# Contributing to time.md

Thank you for your interest in contributing to time.md! This document provides guidelines and information for contributors.

## Code of Conduct

Please be respectful and constructive in all interactions. We're building something together.

## Getting Started

### Prerequisites

- macOS 14.0+ (Sonoma)
- Xcode 26.2+
- Swift 5.9+
- Git

### Setup

1. Fork the repository on GitHub
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/time.md.git
   cd time.md
   ```
3. Open in Xcode:
   ```bash
   open time.md.xcodeproj
   ```
4. Build and run to verify setup:
   ```bash
   make build-mac
   make build-ios
   ```

## Development Workflow

### Branches

- `main` — Stable, release-ready code
- `develop` — Integration branch for features
- `feature/*` — New features
- `fix/*` — Bug fixes
- `docs/*` — Documentation updates

### Making Changes

1. Create a feature branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following the code style guidelines

3. Test your changes:
   ```bash
   make test
   make build-mac
   make build-ios
   ```

4. Commit with clear, descriptive messages:
   ```bash
   git commit -m "Add feature: brief description"
   ```

5. Push to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```

6. Open a Pull Request on GitHub

## Code Style

### Swift Guidelines

- Use Swift's standard naming conventions
- Prefer `let` over `var` when possible
- Use meaningful variable and function names
- Add documentation comments for public APIs
- Use `// MARK: -` to organize code sections

### SwiftUI Guidelines

- Keep views small and focused
- Extract reusable components
- Use `@ViewBuilder` for conditional content
- Prefer composition over inheritance

### Project Structure

```
time.md/
├── App/           # App entry, navigation
├── Data/          # Data services, models
├── Features/      # Feature modules (Overview, Calendar, etc.)
├── DesignSystem/  # Shared UI components, theme
├── Export/        # Export functionality
└── Shared/        # Cross-platform code
```

### Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Views | PascalCase + View suffix | `OverviewView` |
| ViewModels | PascalCase + ViewModel suffix | `CalendarViewModel` |
| Services | PascalCase + Service suffix | `ScreenTimeDataService` |
| Protocols | PascalCase + ing/able suffix | `ScreenTimeProviding` |
| Extensions | Type+Category | `Date+Formatting.swift` |

## Testing

### Running Tests

```bash
make test
```

### Writing Tests

- Place tests in `time.mdTests/`
- Name test files with `Tests` suffix
- Use descriptive test method names
- Test both success and error cases

## Pull Request Guidelines

### Before Submitting

- [ ] Code compiles without warnings
- [ ] Tests pass
- [ ] Code follows style guidelines
- [ ] Documentation is updated if needed
- [ ] Commit messages are clear

### PR Description

Include:
- **What** — Brief description of changes
- **Why** — Motivation for the change
- **How** — Technical approach (if complex)
- **Testing** — How you tested the changes
- **Screenshots** — For UI changes

### Review Process

1. A maintainer will review your PR
2. Address any feedback
3. Once approved, your PR will be merged

## Reporting Issues

### Bug Reports

Include:
- macOS/iOS version
- time.md version
- Steps to reproduce
- Expected behavior
- Actual behavior
- Screenshots/logs if relevant

### Feature Requests

Include:
- Clear description of the feature
- Use case / motivation
- Potential implementation approach (optional)

## Questions?

- Open a GitHub issue for questions
- Check existing issues before creating new ones

## License

By contributing, you agree that your contributions will be licensed under the GNU Affero General Public License v3.0.

---

Thank you for contributing! 🎉
