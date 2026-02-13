# Supported Project Types

MacroManAtlas detects your project type automatically and tailors its indexing strategy accordingly. Detection is performed in priority order -- the first match wins.

## Detection Priority

| Priority | Type ID | Detection Signal |
|----------|---------|-----------------|
| 1 | `cpp-cmake` | `CMakeLists.txt` in repository root |
| 2 | `rust-cargo` | `Cargo.toml` in repository root |
| 3 | `go` | `go.mod` in repository root |
| 4 | `node-workspaces` | `package.json` with `workspaces` field |
| 5 | `dotnet` | `*.sln` or `*.csproj` in repository root |
| 6 | `java-maven` | `pom.xml` in repository root |
| 7 | `java-gradle` | `build.gradle` or `build.gradle.kts` in repository root |
| 8 | `python` | `pyproject.toml`, `setup.py`, or `setup.cfg` in repository root |
| 9 | `dart-flutter` | `pubspec.yaml` in repository root |
| 10 | `generic` | Fallback for any repository |

---

## cpp-cmake

**Detection:** `CMakeLists.txt` exists in the repository root.

**Module discovery:** Directories listed in `add_subdirectory()` calls in the root `CMakeLists.txt`. Each subdirectory with its own `CMakeLists.txt` is treated as a module.

**Purpose extraction:** Parsed from the `project()` command description or inferred from the library/executable name in `add_library()` / `add_executable()`.

**Dependency extraction:** `find_package()`, `target_link_libraries()`, and `FetchContent_Declare()` calls in each module's `CMakeLists.txt`.

**Public API extraction:** Header files in `include/` directories. Interface classes (files matching `I*.h`) are highlighted. Class declarations and key function signatures are summarized.

**Extensions indexed:** `.h`, `.hpp`, `.cpp`, `.cc`, `.cxx`, `.c`, `.cmake`

**Config files included:** `CMakeLists.txt`, `CMakePresets.json`, `*.cmake`

**Example output:**

```markdown
# MacroMan-Detection

ONNX Runtime and TensorRT inference engine.

## Files
| File | Tags | Description |
|------|------|-------------|
| include/detection/OrtDetector.h | detection, inference | ONNX Runtime detector interface |
| src/OrtDetector.cpp | detection, inference | ONNX Runtime implementation |
| src/PostProcessor.cpp | detection, nms | Non-max suppression post-processing |
| CMakeLists.txt | build | Module build configuration |

## Dependencies
- onnxruntime (1.19+)
- OpenCV (4.10)
- Eigen (3.4)

## Public API
- `OrtDetector` -- ONNX Runtime-based object detector
- `TensorRTDetector` -- TensorRT-based object detector
- `PostProcessor` -- NMS and detection filtering
- `DetectorFactory` -- Factory for creating detector instances
```

---

## rust-cargo

**Detection:** `Cargo.toml` exists in the repository root.

**Module discovery:** Workspace members from `[workspace] members` in root `Cargo.toml`. For single-crate projects, the root is treated as one module. Subdirectories with their own `Cargo.toml` are also discovered.

**Purpose extraction:** `description` field in each crate's `Cargo.toml`, or inferred from the crate name.

**Dependency extraction:** `[dependencies]`, `[dev-dependencies]`, and `[build-dependencies]` sections in `Cargo.toml`.

**Public API extraction:** `pub fn`, `pub struct`, `pub enum`, `pub trait` declarations in `src/lib.rs` and `src/main.rs`. Re-exports via `pub use` are followed.

**Extensions indexed:** `.rs`, `.toml`

**Config files included:** `Cargo.toml`, `Cargo.lock`, `rust-toolchain.toml`, `.cargo/config.toml`

**Example output:**

```markdown
# my-crate-core

Shared types and traits for the pipeline.

## Files
| File | Tags | Description |
|------|------|-------------|
| src/lib.rs | core, exports | Crate root with re-exports |
| src/pipeline.rs | core, pipeline | Pipeline trait definitions |
| src/error.rs | core, error | Error types |
| Cargo.toml | build | Crate manifest |

## Dependencies
- serde (1.0)
- tokio (1.x, features: rt-multi-thread)
- tracing (0.1)

## Public API
- `trait Pipeline` -- core pipeline interface
- `struct Config` -- pipeline configuration
- `enum PipelineError` -- error variants
```

---

## go

**Detection:** `go.mod` exists in the repository root.

**Module discovery:** Top-level directories containing `.go` files. Each package directory is a module. For monorepos with multiple `go.mod` files, each is treated as a separate module.

**Purpose extraction:** Package-level doc comment (the comment preceding the `package` declaration) in the package's primary `.go` file.

**Dependency extraction:** `require` block in `go.mod` and `go.sum`.

**Public API extraction:** Exported identifiers (capitalized names): functions, types, interfaces, and constants. Extracted from all `.go` files in the package (excluding `_test.go`).

**Extensions indexed:** `.go`, `.mod`, `.sum`

**Config files included:** `go.mod`, `go.sum`, `Makefile`

**Example output:**

```markdown
# handlers

HTTP request handlers for the API server.

## Files
| File | Tags | Description |
|------|------|-------------|
| auth.go | http, auth | Authentication middleware and login handler |
| users.go | http, users | User CRUD endpoints |
| middleware.go | http, middleware | Request logging and rate limiting |

## Dependencies
- github.com/gin-gonic/gin (v1.9)
- github.com/golang-jwt/jwt/v5

## Public API
- `func NewRouter() *gin.Engine` -- creates configured router
- `func AuthMiddleware() gin.HandlerFunc` -- JWT auth middleware
- `type UserHandler struct` -- user endpoint handler
```

---

## node-workspaces

**Detection:** `package.json` in the repository root with a `workspaces` field (array or object with `packages` key).

**Module discovery:** Glob patterns in the `workspaces` field are resolved. Each matched directory with a `package.json` is a module.

**Purpose extraction:** `description` field in each package's `package.json`.

**Dependency extraction:** `dependencies`, `devDependencies`, and `peerDependencies` from `package.json`.

**Public API extraction:** Named exports from the package entry point (`main`, `exports`, or `index.js`/`index.ts`). For TypeScript projects, `.d.ts` files and type exports are included.

**Extensions indexed:** `.js`, `.ts`, `.jsx`, `.tsx`, `.mjs`, `.cjs`, `.json`

**Config files included:** `package.json`, `tsconfig.json`, `.eslintrc*`, `vite.config.*`, `webpack.config.*`

**Example output:**

```markdown
# @myapp/ui

Shared React component library.

## Files
| File | Tags | Description |
|------|------|-------------|
| src/index.ts | exports | Package entry point |
| src/Button.tsx | component, ui | Button component with variants |
| src/Modal.tsx | component, ui | Modal dialog component |
| src/hooks/useTheme.ts | hook, theme | Theme context hook |

## Dependencies
- react (^18.0.0)
- react-dom (^18.0.0)
- @radix-ui/react-dialog (^1.0)

## Public API
- `Button` -- configurable button component
- `Modal` -- accessible modal dialog
- `useTheme()` -- hook for theme context access
```

---

## dotnet

**Detection:** `*.sln` or `*.csproj` file in the repository root.

**Module discovery:** Projects referenced in the `.sln` file, or directories containing `.csproj` / `.fsproj` / `.vbproj` files.

**Purpose extraction:** `<Description>` element in the `.csproj` file, or inferred from the project/namespace name.

**Dependency extraction:** `<PackageReference>` elements in `.csproj` files and `<ProjectReference>` for inter-project dependencies.

**Public API extraction:** `public class`, `public interface`, `public enum`, and `public static` declarations in `.cs` files. Namespace structure is preserved.

**Extensions indexed:** `.cs`, `.fs`, `.vb`, `.csproj`, `.fsproj`, `.sln`, `.razor`, `.cshtml`

**Config files included:** `*.csproj`, `*.sln`, `appsettings.json`, `Directory.Build.props`, `global.json`, `nuget.config`

**Example output:**

```markdown
# MyApp.Data

Entity Framework data access layer.

## Files
| File | Tags | Description |
|------|------|-------------|
| AppDbContext.cs | data, ef | EF Core database context |
| Models/User.cs | data, model | User entity model |
| Repositories/UserRepository.cs | data, repository | User data access |
| Migrations/Initial.cs | data, migration | Database schema migration |

## Dependencies
- Microsoft.EntityFrameworkCore (8.0)
- Npgsql.EntityFrameworkCore.PostgreSQL (8.0)

## Public API
- `class AppDbContext : DbContext` -- database context
- `interface IUserRepository` -- user data access contract
- `class User` -- user entity
```

---

## java-maven

**Detection:** `pom.xml` in the repository root.

**Module discovery:** `<modules>` section in the root `pom.xml`. Each `<module>` entry with its own `pom.xml` is a module.

**Purpose extraction:** `<description>` element in the module's `pom.xml`, or inferred from `<artifactId>`.

**Dependency extraction:** `<dependencies>` section in `pom.xml`. Scope (compile, test, provided) is noted.

**Public API extraction:** `public class`, `public interface`, `public enum` declarations. Package structure from directory layout under `src/main/java/`.

**Extensions indexed:** `.java`, `.xml` (POM only), `.properties`, `.yaml`, `.yml`

**Config files included:** `pom.xml`, `src/main/resources/application.properties`, `src/main/resources/application.yml`

**Example output:**

```markdown
# myapp-service

REST API service layer.

## Files
| File | Tags | Description |
|------|------|-------------|
| src/main/java/com/myapp/service/UserService.java | service, user | User business logic |
| src/main/java/com/myapp/controller/UserController.java | controller, http | User REST endpoints |
| src/main/java/com/myapp/dto/UserDto.java | dto, user | User data transfer object |

## Dependencies
- org.springframework.boot:spring-boot-starter-web (3.2)
- org.projectlombok:lombok (1.18, provided)
- org.junit.jupiter:junit-jupiter (5.10, test)

## Public API
- `class UserService` -- user business logic
- `class UserController` -- REST endpoint handler
- `interface UserRepository extends JpaRepository` -- data access
```

---

## java-gradle

**Detection:** `build.gradle` or `build.gradle.kts` in the repository root.

**Module discovery:** `include` statements in `settings.gradle` / `settings.gradle.kts`. Each included project with its own build file is a module.

**Purpose extraction:** `description` property in the module's `build.gradle`, or inferred from the project name.

**Dependency extraction:** `dependencies` block in `build.gradle`. Configuration (implementation, api, testImplementation) is noted.

**Public API extraction:** Same as java-maven -- public class/interface/enum declarations, package structure from source directories.

**Extensions indexed:** `.java`, `.kt`, `.kts`, `.gradle`, `.properties`

**Config files included:** `build.gradle`, `build.gradle.kts`, `settings.gradle`, `settings.gradle.kts`, `gradle.properties`

**Example output:**

```markdown
# data-layer

Kotlin data access module with Room and coroutines.

## Files
| File | Tags | Description |
|------|------|-------------|
| src/main/kotlin/com/myapp/data/AppDatabase.kt | data, room | Room database definition |
| src/main/kotlin/com/myapp/data/UserDao.kt | data, dao | User data access object |
| src/main/kotlin/com/myapp/data/UserEntity.kt | data, entity | User database entity |

## Dependencies
- androidx.room:room-runtime (2.6)
- org.jetbrains.kotlinx:kotlinx-coroutines-core (1.8)

## Public API
- `class AppDatabase : RoomDatabase` -- database singleton
- `interface UserDao` -- user query interface
- `data class UserEntity` -- user table mapping
```

---

## python

**Detection:** `pyproject.toml`, `setup.py`, or `setup.cfg` in the repository root.

**Module discovery:** Top-level Python packages (directories with `__init__.py`). For monorepos with `src/` layout, packages under `src/` are discovered. Namespace packages (PEP 420) are also detected.

**Purpose extraction:** `description` from `pyproject.toml` `[project]` section, `setup()` call in `setup.py`, or `[metadata]` in `setup.cfg`. Per-package docstrings from `__init__.py`.

**Dependency extraction:** `dependencies` / `requires` from `pyproject.toml`, `install_requires` from `setup.py`, or `requirements.txt`.

**Public API extraction:** Module-level `__all__` list, public functions and classes (names not starting with `_`), and type-annotated signatures.

**Extensions indexed:** `.py`, `.pyi`, `.toml`, `.cfg`, `.txt` (requirements only)

**Config files included:** `pyproject.toml`, `setup.py`, `setup.cfg`, `requirements*.txt`, `tox.ini`, `mypy.ini`

**Example output:**

```markdown
# mypackage.core

Core processing pipeline and configuration.

## Files
| File | Tags | Description |
|------|------|-------------|
| __init__.py | core, exports | Package initialization and public API |
| pipeline.py | core, pipeline | Data processing pipeline |
| config.py | core, config | Configuration dataclass |
| exceptions.py | core, error | Custom exception hierarchy |

## Dependencies
- pydantic (>=2.0)
- structlog
- click

## Public API
- `class Pipeline` -- main data processing pipeline
- `class Config` -- pipeline configuration (Pydantic model)
- `def run(config: Config) -> Result` -- entry point
```

---

## dart-flutter

**Detection:** `pubspec.yaml` in the repository root.

**Module discovery:** For Flutter apps: `lib/` subdirectories by feature. For monorepos with `melos.yaml` or `packages/` directory: each package with its own `pubspec.yaml`.

**Purpose extraction:** `description` field in `pubspec.yaml`.

**Dependency extraction:** `dependencies` and `dev_dependencies` in `pubspec.yaml`.

**Public API extraction:** Public Dart classes, mixins, and top-level functions from `lib/` files. Exports declared in the package's barrel file (`lib/<package_name>.dart`).

**Extensions indexed:** `.dart`, `.yaml`, `.arb` (localization)

**Config files included:** `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `build.yaml`, `melos.yaml`

**Example output:**

```markdown
# my_app

Cross-platform task management app built with Flutter.

## Files
| File | Tags | Description |
|------|------|-------------|
| lib/main.dart | app, entry | Application entry point |
| lib/features/tasks/task_list_page.dart | feature, ui | Task list screen |
| lib/features/tasks/task_model.dart | feature, model | Task data model |
| lib/services/api_service.dart | service, http | REST API client |

## Dependencies
- flutter_riverpod (^2.4)
- dio (^5.4)
- freezed_annotation (^2.4)

## Public API
- `class TaskListPage extends ConsumerWidget` -- task list UI
- `class TaskModel` -- immutable task data class
- `class ApiService` -- REST client for backend
```

---

## generic

**Detection:** Fallback -- used when no other project type matches.

**Module discovery:** All top-level directories (excluding hidden directories, `node_modules`, `build`, `dist`, `target`, `.git`).

**Purpose extraction:** Inferred from directory name and README files if present.

**Dependency extraction:** Not applicable (no standard manifest to parse).

**Public API extraction:** Heuristic-based: files with common entry point names (`main.*`, `index.*`, `app.*`, `lib.*`) are highlighted. Public-looking declarations are extracted where language detection succeeds.

**Extensions indexed:** All text files tracked by git (via `git ls-files`).

**Config files included:** Any recognized config files (`.json`, `.yaml`, `.yml`, `.toml`, `.ini`, `.cfg`) in the repository root.

**Example output:**

```markdown
# scripts

Utility scripts and automation.

## Files
| File | Tags | Description |
|------|------|-------------|
| deploy.sh | ops, deploy | Production deployment script |
| migrate.py | ops, database | Database migration runner |
| setup.sh | ops, setup | Development environment setup |
```
