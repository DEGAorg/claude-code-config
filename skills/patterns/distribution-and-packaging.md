<!-- Sources: Canon_MVP_Technical_Roadmap.md (Open Core Distribution, Why Alternative B, Harness Engineering Patterns), SAS_Automation_Model.md (Dogfooding, Design Principles, canon.manifest.yaml) -->

# Distribution and Packaging

Patterns for open-source distribution, dogfooding, and build-time packaging.

## Open core boundary

Open-source the framework that grows the ecosystem (tools, skills,
templates). Monetize the platform that captures value (dashboard,
execution, marketplace). Draw the line explicitly.

## Dogfooding

Build with your own tools. Internal usage drives quality. Patterns
discovered while building become first-party features. If you wouldn't
use it yourself, don't ship it.

## Spec-grounded implementation

Every implementation task must be grounded in a specification. If no spec
exists, write one first. Specs prevent scope creep and miscommunication
between agents and between humans and agents.

## Plugin-first development

Build a feature as a plugin first. Test it with users. Promote to core
if successful. This proves demand before committing to core integration
and keeps the core lean.

## Deferred decisions

Don't force users to choose architecture upfront. Start building; defer
packaging and targeting decisions until build time. Same code, different
targets.

## Manifest-driven packaging

A single manifest file declares capabilities, dependencies, and build
targets. Packaging happens at build time, not project-creation time.
No template proliferation.

## Single abstraction

Everything follows one development pattern. Plugins, agents, services,
and automations all use the same project structure, manifest format, and
lifecycle. Reduces cognitive load across the ecosystem.
