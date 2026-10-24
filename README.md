# Connectome

Create a portable database expert skill from database access, useful SQL, documentation, and a subject matter expert. The resulting `[database]-expert` folder gives another agent enough context to query one source and write new SQL.

Connectome v0.1 is a factory skill for desktop and coding agents with local files, a shell, and access to the database. It uses [usql](https://github.com/xo/usql) directly. Generated skills follow the [Agent Skills format](https://agentskills.io/specification).

## Start

Download or clone this repository, then ask your agent to open [skills/connectome/SKILL.md](skills/connectome/SKILL.md). For automatic discovery, have the agent install the whole `skills/connectome` folder in its supported skill directory.

The agent handles client setup, file placement, query checks, and packaging. You provide the source you use, the question you need to answer, and any useful SQL or documentation.

### Create

> Use Connectome to create a skill for our sales database. I connect through [SQL app]. Start with [a question I need to answer]. I have existing queries and documentation to share.

### Extend

> Use Connectome to extend this [database]-expert folder for [a new question]. [Person] knows this part of the source. Start from the recorded gaps and preserve the supported guidance.

The subject matter expert supplies meaning and checks the agent's interpretation. They can say "I don't know." The agent records consequential unknowns so another expert can continue later.

## Use and share the result

Open the generated folder's `SKILL.md` to use the source. Its links lead to relevant context, useful SQL, and setup or renewal guidance. Context explains the grain, joins, dates, units, exclusions, and limits that matter for the captured use.

Share the folder or ZIP through your usual file-sharing channel. Ask the recipient's agent to open `SKILL.md` and establish the recipient's own connection. Analysts do not need Git or the original conversation.

After meaningful use, the agent keeps supported corrections with the affected context or SQL. It can ask whether you want to share a substantive improvement. Contribution review, merging, and stewardship remain in your separate process.

## Access assumptions

Connections use usql's [native configuration](https://github.com/xo/usql#configuration). Optional Bash and Windows PowerShell helpers accept a username and password through a local hidden prompt and save one private connection file. That file persists across client processes, with renewal when credentials change or expire. Existing profiles and the default configuration remain untouched. Passwords are plaintext; restrictive filesystem permissions limit who can read them. No credential service or additional runtime is required by the helpers.

Each teammate supplies their own access. Credentials and raw query results stay out of generated skills and shared packages. Use read-only database permissions where available.

Database drivers and authentication support belong to upstream usql and the installed client build. Connectome preserves the source's SQL dialect. The consuming agent owns downstream analysis and work across sources.

## Public example

The first proving case is Microsoft's [Wide World Importers](https://learn.microsoft.com/en-us/sql/samples/wide-world-importers-what-is?view=sql-server-ver17), using the [Full SQL Server OLTP backup](https://github.com/microsoft/sql-server-samples/releases/tag/wide-world-importers-v1.0). This is a public sample downloaded for local restore, not a live public database service.

The [WWI expert skill](examples/wide-world-importers-expert/SKILL.md) includes source context, standalone setup, and executable T-SQL. The [proving-case record](tests/wwi/README.md) describes the original fixture, independent controls, agent handoff, and verified limits. The source has 48 physical tables, 70,510 invoices, and 228,265 invoice lines; the skill deepens only the areas needed for its retrieval tasks.

## Design principles

The factory keeps a few rules close to the work:

- Start with a real retrieval need and existing useful SQL.
- Give each fact one home. Add references only when selective reading helps.
- Distinguish documented facts, observations, expert explanations, and unknowns.
- Check returned data against an independent expectation and state what remains unproven.
- Preserve existing connections and unrelated knowledge when extending a skill.

These choices draw on [poteto/plugins](https://github.com/poteto/plugins) and [backnotprop/pstack](https://github.com/backnotprop/pstack). Neither is a runtime dependency.

## Next work

1. Run a real analyst and teammate through Create, use, and Extend in a desktop agent. Verify the human can enter credentials locally, the saved connection survives an app restart, and the shared folder works without the original conversation. Complete Windows host verification.
2. Try a second engine and a different native authentication path. Change the factory only for a demonstrated gap; keep database and authentication support upstream.
3. Add a workbook or SharePoint source factory when an actual retrieval need justifies it. A coordinating factory and cloud-only support follow proven source factories.

Improve the two existing entry paths before adding more. Submission, review, and stewardship remain external.

## License

Connectome uses the [MIT license](LICENSE). Referenced tools, documentation, and sample databases retain their upstream licenses.
