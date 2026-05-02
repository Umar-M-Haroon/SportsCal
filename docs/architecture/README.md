# Architecture Documentation — moved to DocC

The architecture overview has moved into the SportsCalModel DocC catalog. The mermaid `.mmd` source files in this directory remain the editable source of truth for the diagrams — they're pre-rendered to SVG and shipped inside the DocC catalog's `Resources/`.

**Articles:**

- [`SportsCalModel/Sources/SportsCalModel/SportsCalModel.docc/Articles/DataModel.md`](../../SportsCalModel/Sources/SportsCalModel/SportsCalModel.docc/Articles/DataModel.md) — model relationships, system overview, data flow.
- [`SportsCalModel/Sources/SportsCalModel/SportsCalModel.docc/Articles/ApiVersioning.md`](../../SportsCalModel/Sources/SportsCalModel/SportsCalModel.docc/Articles/ApiVersioning.md) — API versioning strategy, endpoint inventory.

Build the docs locally:

```bash
cd SportsCalModel
swift package generate-documentation --target SportsCalModel
open .build/plugins/Swift-DocC/outputs/SportsCalModel.doccarchive
```

## Regenerating diagrams

The `.mmd` files here are still the source for the SVGs that render in the DocC articles. To regenerate after editing:

```bash
cd docs/architecture
for f in overview data-flow models api-endpoints; do
  npx -y -p @mermaid-js/mermaid-cli mmdc -i "$f.mmd" -o "/tmp/$f.svg" -b transparent
done
cp /tmp/{overview,data-flow,models,api-endpoints}.svg \
  ../../SportsCalModel/Sources/SportsCalModel/SportsCalModel.docc/Resources/
```
