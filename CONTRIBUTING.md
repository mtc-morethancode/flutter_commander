# Contributing to `flutter_commander` 🐦

Thank you for your interest in contributing to **`flutter_commander`**!

We welcome contributions from the community—whether it's reporting bugs, improving documentation, submitting feature ideas, or opening pull requests.

To maintain architectural integrity, test coverage, and a smooth development experience, please read through these guidelines before submitting a contribution.

---

## 🏛️ Architectural Principles

Before writing code, keep in mind the core pillars that guide `flutter_commander`:

1. **Zero Code Generation:** 100% pure Dart 3. Instant compilation, transparent stack traces, and zero build runner overhead.
2. **Strict Decoupling (MVI):** Unidirectional flow (`Intent -> Command -> State / SideEffect`). UI widgets must never execute business logic directly.
3. **Atomic Commands:** Each command is an isolated unit of work owning its execution policy, concurrency control, and cancellation contract.
4. **Deterministic Testing:** All features and bug fixes must be verified via our two-tier testing suite (`commanderTest` or `TestCommandScope`).
5. **No External Bloat:** Keep external dependencies to the absolute bare minimum (`meta`, `matcher`, `test_api`).

---

## 🚀 How to Contribute

### 1. Reporting Bugs

If you find a bug:
1. Search [existing GitHub Issues](https://github.com/mtc-morethancode/flutter_commander/issues) to ensure it hasn't already been reported.
2. Open a new issue with:
   * A clear, descriptive title.
   * Steps to reproduce the behavior.
   * Expected vs. actual behavior.
   * Flutter & Dart SDK versions (`flutter doctor -v`).
   * A minimal reproducible example or test case demonstrating the issue.

### 2. Proposing New Features

For non-trivial features, architectural extensions, or API changes:
* **Open an Issue first** to discuss your proposal before writing code.
* Explain the problem being solved, the proposed API contract, and why it fits within `flutter_commander`'s vision.
* This ensures alignment and saves you from writing code that might not fit the framework's roadmap.

---

## 💻 Local Development Workflow

### Prerequisites
* **Flutter SDK**: `>= 3.10.0`
* **Dart SDK**: `>= 3.0.0 < 4.0.0`
* **Git**

### Step-by-Step Setup

1. **Fork and Clone the Repository:**
   ```bash
   git clone https://github.com/<your-username>/flutter_commander.git
   cd flutter_commander
   ```

2. **Create a Feature Branch:**
   Use clear branch naming following our conventions:
   * `feat/your-feature-name`
   * `fix/bug-description`
   * `docs/documentation-update`
   * `refactor/clean-up-scope`

   ```bash
   git checkout -b feat/my-new-feature
   ```

3. **Install Dependencies:**
   ```bash
   flutter pub get
   ```

4. **Run the Test Suite:**
   All 190+ tests must pass:
   ```bash
   flutter test
   ```

5. **Run Static Analysis:**
   Ensure zero analyzer warnings or hints:
   ```bash
   flutter analyze
   ```

6. **Verify the Example Project:**
   ```bash
   cd example
   flutter pub get
   flutter test
   flutter analyze
   cd ..
   ```

---

## 🧪 Testing Standards

We maintain very high standards for test reliability. Every Pull Request must include automated tests:

* **Orchestrator & Flow Verification:** Use `commanderTest` from `package:flutter_commander/testing.dart` to assert state emissions, side-effects, and initial state seeding.
* **Isolated Unit Tests:** Use `TestCommandScope` for testing individual `Command` logic deterministically without widgets or streams.
* **Regression Tests:** When fixing a bug, write a test that reproduces the bug *first*, and then ensure it passes with your fix.

---

## 📝 Commit Conventions

We follow **Conventional Commits** in English. Messages should be structured as:

```text
<type>(<scope>): <short description in imperative mood>

[optional body explaining rationale]
```

### Types:
* `feat`: A new user-facing feature or API.
* `fix`: A bug fix.
* `docs`: Documentation changes, README updates, or website guides.
* `test`: Adding or correcting tests.
* `refactor`: Code changes that neither fix a bug nor add a feature.
* `perf`: Performance improvements.
* `chore`: Build scripts, CI workflow, or tool updates.

**Examples:**
* `feat(concurrency): add custom timeout support to ExecutionPolicy.drop`
* `fix(cancellation): guarantee token cleanup on synchronous command failure`
* `docs(readme): clarify two-tier testing section`

---

## 🔀 Submitting a Pull Request

When your branch is ready:

1. Push your branch to your fork:
   ```bash
   git push origin feat/my-new-feature
   ```
2. Open a Pull Request against the `main` branch of `mtc-morethancode/flutter_commander`.
3. Fill out the PR template with:
   * Summary of changes.
   * Linked issue (`Closes #123`).
   * Confirmation that all tests and analyzer checks pass.
4. **Code Owner Approval:**
   * In accordance with our governance rules, all pull requests require review and approval from `@garispe` (Code Owner).
   * Automated CI workflows (`Lint, Test & Validate`) must pass before merging.

---

## 📄 License

By contributing to `flutter_commander`, you agree that your contributions will be licensed under the project's [MIT License](LICENSE).
