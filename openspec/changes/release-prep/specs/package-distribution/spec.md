## Purpose

What the published term-ui packages guarantee to someone who installs them: that dependencies reflect what the code actually imports, that the documented API is the real one and is correctly typed, that licensing and provenance are stated, and that a clean install renders.

## ADDED Requirements

### Requirement: Dependencies reflect actual imports

Every entry in a published package's `dependencies` SHALL be imported by that package's shipped code. Packages needed only to build or type-check SHALL be `devDependencies`, and packages needed only by an unpublished experiment SHALL NOT appear in a published manifest at all.

#### Scenario: Installing pulls no unused transitive tree

- **WHEN** a published package is installed into an empty project
- **THEN** no dependency is present that the package's shipped code never imports

#### Scenario: Experiment-only dependencies are absent

- **WHEN** a module is excluded from a package's published export surface
- **THEN** the dependencies that only that module imports are absent from the package's `dependencies`

### Requirement: Experiments are not publishable

Packages in the repository that are experiments or internal tooling SHALL be marked private so they cannot be published accidentally. Published package names SHALL match the project's scope exactly.

#### Scenario: Publishing skips experiments

- **WHEN** a repository-wide publish is performed
- **THEN** only the packages intended as products are published, and experiments are skipped

### Requirement: The documented API is the real API

Each published package's README SHALL document the API that package currently exposes, and every code example in it SHALL run against the published version. No published package SHALL ship an empty README.

#### Scenario: A reader follows the quickstart

- **WHEN** someone copies the quickstart example from a published package's README into a new project
- **THEN** it compiles and renders without modification

### Requirement: Host elements are correctly typed in JSX

The React package SHALL provide types for its own host elements such that element props — including `contentEditable` and event handlers — type-check without casts, and unknown props are rejected. Host element types SHALL NOT resolve to unrelated elements from other renderers.

#### Scenario: Element props type-check

- **WHEN** an application uses the package's documented JSX configuration and passes a supported prop to a host element
- **THEN** the prop type-checks with no cast, and its event handler parameters are typed

#### Scenario: Unsupported props are caught

- **WHEN** an application passes a prop that host elements do not support
- **THEN** type checking reports an error rather than silently accepting it

### Requirement: Licensing and provenance are stated

Every published package SHALL declare a license identifier and carry the license text, and SHALL point at the project's real repository. Stated licensing SHALL be consistent across manifests, license files, and documentation.

#### Scenario: A consumer audits the package

- **WHEN** license and repository metadata are read from an installed package
- **THEN** the license is declared and matches the included license text, and the repository location is the project's actual repository

### Requirement: A packaged install renders

The packaged artifacts SHALL be sufficient to render on their own: a project that installs the built tarballs and follows the quickstart SHALL produce terminal output without needing the source repository.

#### Scenario: Clean-room install

- **WHEN** the packages are packed and installed into a project outside the repository, and the quickstart program is run
- **THEN** it renders its expected output and exits cleanly
