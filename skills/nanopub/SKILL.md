---
name: nanopub
description: Create, sign, publish, query, or retract nanopublications
argument-hint: [nanopub URL, description, or action]
---

Help the user work with nanopublications. This includes creating new nanopubs, fetching and inspecting existing ones, superseding or retracting nanopubs, and publishing to the test server or live network.

## Creating an Agent/Bot Identity

To publish nanopubs on behalf of a software agent (bot), you need to create a dedicated identity with its own key pair and introduction nanopub.

### Generate an RSA key pair

```bash
openssl genrsa -out ~/.nanopub/<agent>_id_rsa 2048
openssl rsa -in ~/.nanopub/<agent>_id_rsa -pubout -outform PEM -out ~/.nanopub/<agent>_id_rsa.pub
```

Extract the public key as a single-line base64 string (needed for the introduction nanopub):

```bash
grep -v '^\-' ~/.nanopub/<agent>_id_rsa.pub | tr -d '\n'
```

**Never delete or alter key files in `~/.nanopub/`** — they are required to sign and retract nanopubs published with that identity. Losing a key means losing the ability to manage those nanopubs.

### Create an introduction nanopub

The introduction nanopub declares the agent's identity, links it to an owner (via ORCID), and registers its public key. The agent's IRI is typically a sub-IRI of this nanopub itself (e.g. `sub:agent-name`), which gets resolved to a full trusty URI after signing.

```turtle
@prefix this: <http://purl.org/nanopub/temp/np001/> .
@prefix sub: <http://purl.org/nanopub/temp/np001/> .
@prefix np: <http://www.nanopub.org/nschema#> .
@prefix dct: <http://purl.org/dc/terms/> .
@prefix npx: <http://purl.org/nanopub/x/> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix orcid: <https://orcid.org/> .
@prefix prov: <http://www.w3.org/ns/prov#> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .

sub:Head {
  this: a np:Nanopublication ;
    np:hasAssertion sub:assertion ;
    np:hasProvenance sub:provenance ;
    np:hasPublicationInfo sub:pubinfo .
}

sub:assertion {
  sub:agent-name a npx:Bot, npx:SoftwareAgent ;
    foaf:name "Agent Display Name" ;
    <http://purl.org/vocab/frbr/core#owner> orcid:OWNER-ORCID .

  sub:decl npx:declaredBy sub:agent-name ;
    npx:hasAlgorithm "RSA" ;
    npx:hasPublicKey "PUBLIC-KEY-BASE64" .
}

sub:provenance {
  sub:assertion prov:wasAttributedTo orcid:OWNER-ORCID .
}

sub:pubinfo {
  this: dct:created "TIMESTAMP"^^xsd:dateTime ;
    rdfs:label "Agent Display Name" ;
    dct:creator sub:agent-name ;
    dct:license <https://creativecommons.org/licenses/by/4.0/> ;
    npx:hasNanopubType npx:declaredBy ;
    npx:introduces sub:agent-name .

  orcid:OWNER-ORCID foaf:name "Owner Name" .
}
```

### Sign and publish the introduction

Sign the introduction with the **agent's own key** (not the owner's key):

```bash
java -jar "$JAR" sign -k ~/.nanopub/<agent>_id_rsa -o tmp/<agent>-intro-signed.trig tmp/<agent>-intro.trig
java -jar "$JAR" publish tmp/<agent>-intro-signed.trig
```

After publishing, note the trusty URI — the agent's IRI becomes `<trusty-uri>/<agent-name>` (e.g. `https://w3id.org/np/RAxxxxx/agent-name`). Use this IRI as `dct:creator` and for `-s` when signing/retracting nanopubs with this agent.

### Using the agent identity

When creating nanopubs as this agent, sign with `-k` and use the agent IRI as creator:

```bash
java -jar "$JAR" sign -k ~/.nanopub/<agent>_id_rsa -o tmp/<name>-signed.trig tmp/<name>.trig
```

When retracting, specify the agent as signer:

```bash
java -jar "$JAR" retract -i <nanopub-uri> -k ~/.nanopub/<agent>_id_rsa -s <agent-IRI> -p
```

## Nanopublication Structure

Every nanopub (`.trig` file) contains four named graphs:

1. **Head** — links to the other three graphs
2. **Assertion** — the semantic claims (domain-specific RDF triples)
3. **Provenance** — attribution and source references (e.g. `prov:wasAttributedTo`, `prov:wasDerivedFrom`)
4. **PublicationInfo** — metadata (creator, timestamp, license), and RSA signature (in signed versions)

## Workflow

### 1. Determine the action

The user may want to:
- **Create** a new nanopub from RDF content, a claim, a shape, or other structured content
- **Fetch/inspect** an existing nanopub by URL or trusty ID
- **Query** nanopubs via Nanopub Query (the grlc-based SPARQL query API)
- **Supersede** an existing nanopub with updated content
- **Retract** a published nanopub

If the argument is `$ARGUMENTS`, use that as the starting point.

#### Fetching an existing nanopub

Fetch via HTTP GET with `Accept: application/trig`:

```bash
curl -s -L -H "Accept: application/trig" "<nanopub-url>"
```

Display the nanopub URI, full TriG content, and a summary of the named graphs.

#### Querying nanopubs via Nanopub Query

Nanopub Query is a grlc-based API that exposes published SPARQL query templates as REST endpoints. The base instance is at `https://query.knowledgepixels.com/`.

**Discovering available queries:**

To list all available queries at the current point in time, use the `get-queries` meta-query:

```bash
curl -s "https://query.knowledgepixels.com/api/RAQqjXQYlxYQeI4Y3UQy9OrD5Jx1E3PJ8KwKKQlWbiYSw/get-queries"
```

This returns all published query templates and can be used as a starting point to find queries relevant to a given task.

**Downloading all query templates locally:**

Run the [download script](scripts/download-queries.sh) to fetch all query template nanopublications as individual TriG files into the [queries/](queries/) folder:

```bash
bash skills/nanopub/scripts/download-queries.sh
```

This is useful for browsing, searching, or analyzing the full set of available queries offline. Files are named `<trusty-id>_<label>.trig`. Re-running the script skips already-downloaded files.

**Downloading all assertion templates locally:**

Similarly, run the [assertion template download script](scripts/download-assertion-templates.sh) to fetch all assertion template nanopublications into the [assertion-templates/](assertion-templates/) folder:

```bash
bash skills/nanopub/scripts/download-assertion-templates.sh
```

Assertion templates define the structure for creating nanopubs of a specific type (e.g. expressing a claim, defining a class, declaring event participation). They can be listed via the API:

```bash
curl -s "https://query.knowledgepixels.com/api/RA6bgrU3Ezfg5VAiLru0BFYHaSj6vZU6jJTscxNl8Wqvc/get-assertion-templates"
```

**Downloading all resource views locally:**

Run the [resource view download script](scripts/download-resource-views.sh) to fetch all resource view nanopublications into the [resource-views/](resource-views/) folder:

```bash
bash skills/nanopub/scripts/download-resource-views.sh
```

Resource views define how data is displayed on resource pages (user/space/maintained resource pages). They specify a query, view type (tabular, list, nanopub set, etc.), and optional action templates. They can be listed via the API:

```bash
curl -s "https://query.knowledgepixels.com/api/RAcyg9La3L2Xuig-jEXicmdmEgUGYfHda6Au1Pfq64hR0/get-all-resource-views"
```

To browse the OpenAPI spec for a specific published query:

```
https://query.knowledgepixels.com/openapi/?url=spec/<ARTIFACT-CODE>/<query-local-name>
```

Where `<ARTIFACT-CODE>` is the trusty ID (e.g. `RAxxx...`) and `<query-local-name>` is the query's local name from the assertion.

**grlc query template syntax:**

Nanopub SPARQL templates use an extended version of the grlc syntax for placeholders:

- **Required placeholders** start with a single underscore: `?_name` (literal) or `?_resource_iri` (IRI, suffix `_iri`)
- **Optional placeholders** start with two underscores: `?__filter_iri` or `?__filtertext` — these don't need to be filled before running the query
- **Multi-value placeholders** have the suffix `_multi` (literal) or `_multi_iri` (IRI), e.g. `?_resource_multi_iri`. These accept 1 or more values and require a `values ?_resource_multi_iri {}` statement in the SPARQL to indicate where values are filled in
- **Optional multi-value placeholders** combine both: `?__resource_multi_iri` accepts 0 or more values

**API parameter naming:** The SPARQL variable name is stripped of its prefix and suffix to form the API parameter name. For example, `?_user_iri` becomes just `user` in the API, not `_user_iri`.

**Result column labels:** When a result column holds a URI, the UI renders it nicely if there is a companion `?<name>_label` variable. For example, a `?view` column with a `?view_label` variable will display the label text linked to the URI. For nanopub URI columns, use `("^" as ?np_label)` to show a short clickable symbol instead of the full URI. Always place `?np` and `?np_label` as the last columns in the SELECT clause.

**Calling a query via the API:**

```bash
curl -s "https://query.knowledgepixels.com/api/<ARTIFACT-CODE>/<query-local-name>?<param1>=<value1>&<param2>=<value2>"
```

- The response is typically CSV or JSON depending on the `Accept` header
- Add `Accept: text/csv` for CSV or `Accept: application/json` for JSON results

**Testing an unpublished query template:**

Before publishing a query template nanopub, you can test it by base64url-encoding the signed TriG and passing it as the `_nanopub_trig` parameter:

```bash
# Base64url-encode the signed nanopub
NP_B64=$(base64 -w0 tmp/<name>-signed.trig | tr '+/' '-_' | tr -d '=')

# Extract the artifact code from the signed file
ARTIFACT=$(head -1 tmp/<name>-signed.trig | grep -oP 'RA[A-Za-z0-9_-]{43}')

# Call the API with the encoded nanopub
curl -s "https://query.knowledgepixels.com/api/${ARTIFACT}/<query-local-name>?<param>=<value>&_nanopub_trig=${NP_B64}"
```

Or open the OpenAPI UI for interactive testing in the user's browser:

```bash
NP_B64=$(base64 -w0 tmp/<name>-signed.trig | tr '+/' '-_' | tr -d '=')
ARTIFACT=$(head -1 tmp/<name>-signed.trig | grep -oP 'RA[A-Za-z0-9_-]{43}')
xdg-open "https://query.knowledgepixels.com/openapi/?url=spec/${ARTIFACT}/<query-local-name>&_nanopub_trig=${NP_B64}"
```

### 2. Check the user's profile

Before creating the TriG file, read `~/.nanopub/profile.yaml` to get the user's ORCID:

```bash
cat ~/.nanopub/profile.yaml
```

If `orcid_id` is missing or empty, warn the user: without it, the `sign` command will omit `npx:signedBy` from the signature, which makes the nanopub unlinked from a person. Ask the user to add their ORCID to the profile before proceeding.

### 3. Create the TriG file

Write the nanopub directly as a TriG file in `tmp/`. Use a placeholder base URI with a trailing slash — the `sign` command will replace it with the trusty URI everywhere.

Get the current UTC timestamp by running:

```bash
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Template:

```turtle
@prefix this: <http://purl.org/nanopub/temp/np001/> .
@prefix sub: <http://purl.org/nanopub/temp/np001/> .
@prefix np: <http://www.nanopub.org/nschema#> .
@prefix dct: <http://purl.org/dc/terms/> .
@prefix npx: <http://purl.org/nanopub/x/> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix orcid: <https://orcid.org/> .
@prefix prov: <http://www.w3.org/ns/prov#> .
# ... add any domain-specific prefixes needed for the assertion ...

sub:Head {
  this: a np:Nanopublication ;
    np:hasAssertion sub:assertion ;
    np:hasProvenance sub:provenance ;
    np:hasPublicationInfo sub:pubinfo .
}

sub:assertion {
  # ... assertion triples ...
}

sub:provenance {
  # Use one or both depending on the origin of the assertion content:
  # If content was derived/extracted from an external source:
  # sub:assertion prov:wasDerivedFrom <source-url> .
  # If the user authored the content:
  # sub:assertion prov:wasAttributedTo orcid:USER-ORCID .
  # If both (e.g. user modified content from an external source), include both triples.
}

sub:pubinfo {
  this: dct:created "TIMESTAMP"^^xsd:dateTime ;  # ← replace with current UTC time
    rdfs:label "short human-readable label" ;  # can be omitted if an introduced resource already has an rdfs:label in the assertion
    dct:creator orcid:USER-ORCID ;
    dct:license <https://creativecommons.org/licenses/by/4.0/> .
    # only if the nanopub supersedes an earlier one:
    # npx:supersedes <original-nanopub-uri> .
    # only if the nanopub introduces a new concept/resource as its main element:
    # npx:introduces <main-element-IRI> .
    # only if created at a specific tool instance (e.g. nanodash):
    # npx:wasCreatedAt <https://nanodash.knowledgepixels.com/> .
}
```

### 4. Validate and sign

First, ensure the nanopub CLI jar is available. If not already present, download the latest release from Maven Central:

```bash
NP_VERSION=$(curl -s "https://repo1.maven.org/maven2/org/nanopub/nanopub/maven-metadata.xml" | grep -o '<release>[^<]*</release>' | sed 's/<[^>]*>//g')
JAR="nanopub-${NP_VERSION}-jar-with-dependencies.jar"
if [ ! -f "$JAR" ]; then
  curl -L -o "$JAR" "https://repo1.maven.org/maven2/org/nanopub/nanopub/${NP_VERSION}/${JAR}"
fi
```

**Validate** the TriG file before signing to catch structural errors early:

```bash
java -jar "$JAR" check tmp/<name>.trig
```

**Sign** with the default user key (from `~/.nanopub/profile.yaml`):

```bash
java -jar "$JAR" sign -o tmp/<name>-signed.trig tmp/<name>.trig
```

To sign with a **specific key** (e.g. for a bot identity):

```bash
java -jar "$JAR" sign -k ~/.nanopub/<bot>_id_rsa -o tmp/<name>-signed.trig tmp/<name>.trig
```

**After signing, always verify** that `npx:signedBy` is present before publishing:

```bash
grep "signedBy" tmp/<name>-signed.trig
```

If `npx:signedBy` is absent, the user's ORCID was not found in the profile. Stop, ask the user to add it to `~/.nanopub/profile.yaml`, and re-sign.

### 5. Test query template nanopubs before publishing

If the nanopub contains a grlc query template (i.e. has a `grlc:sparql` predicate in its assertion), **always test it before publishing** using the unpublished query testing method described in the "Querying nanopubs via Nanopub Query" section above. Verify the results look correct before proceeding to publish.

### 6. Ask about publishing target, then publish

Ask: **test server or live network?**

```bash
# Test server
java -jar $JAR publish --server https://test.registry.knowledgepixels.com/ tmp/<name>-signed.trig

# Live network
java -jar $JAR publish tmp/<name>-signed.trig
```

### 7. Retract a nanopub (if a bad version was published)

```bash
# Retract using the default user key:
java -jar $JAR retract -i <nanopub-uri> -p

# Retract using a specific key (e.g. for bot nanopubs) — requires -s <signer-IRI>:
java -jar $JAR retract -i <nanopub-uri> -k ~/.nanopub/<bot>_id_rsa -s <signer-IRI> -p
```

The `-p` flag publishes the retraction immediately. When using a specific key (`-k`), you must also specify the signer IRI (`-s`), which can be an ORCID or a bot IRI.

### 8. Create a nanopub index

A nanopub index groups multiple nanopubs under a single entry point:

```bash
java -jar $JAR mkindex -o index.trig -t "Index title" file1.trig file2.trig ...
```

To supersede an existing index:

```bash
java -jar $JAR mkindex -x <old-index-uri> -o new-index.trig -t "Index title" file1.trig file2.trig ...
```

The `-x` flag automatically adds the `npx:supersedes` link. After creating, sign and publish as usual.

### 9. Report result

Show:
- The new nanopub trusty URI
- If supersedes: confirm the `npx:supersedes` link
- If introduces: note the introduced resource

## Important Notes

- **Never write a Java class** for one-off nanopub creation. Always create the TriG file directly and use the CLI jar.
- Download the CLI jar from Maven Central if not present (see step 4); reuse it across invocations by keeping it in the working directory.
- Nanopubs use **trusty URIs** — the `sign` command computes and replaces the placeholder URI everywhere in the file.
- The temp URI must end with `/` so sub-resources are correctly derived and transformed.
- Never copy the original nanopub's author ORCID into `dct:creator`/`prov:wasAttributedTo` — always use the current user's ORCID from their profile.
- Always get the current UTC time by running `date -u +"%Y-%m-%dT%H:%M:%SZ"` for `dct:created` timestamps. Never use a date-only or zeroed time.
- If a bad nanopub was published (e.g. missing `npx:signedBy`), retract it with `retract -i <uri> -p` before publishing the corrected version.
- Provenance should reflect the actual origin of the assertion content: use `prov:wasDerivedFrom` when content comes from an external source, `prov:wasAttributedTo` when the user authored it, or both when the user modified external content.
- Add `npx:introduces` in pubinfo pointing to the main element of the assertion when the nanopub introduces a new concept or resource (e.g. a new shape, class, or query definition).
- Always add an `rdfs:label` on `this:` in pubinfo with a short human-readable label for the nanopub. This can be omitted only if the nanopub has an introduced resource (via `npx:introduces`) that already has an `rdfs:label` in the assertion graph.
- Only add `npx:wasCreatedAt` if the nanopub was actually created at that specific tool instance. Do not add it by default.
- The temp URI **must** use the `http://purl.org/nanopub/temp/` prefix (e.g. `http://purl.org/nanopub/temp/np001/`). Using `https://w3id.org/np/temp` instead causes the signed trusty URI to be malformed.
- **Personal information policy**: Only include personal information (names, emails, affiliations, ORCIDs) in a nanopub if it is already permanently and openly published (e.g. in a published paper or made available by the person under an open license).
- When it seems likely that a similar nanopub may already exist on the network (e.g. for well-known resources, popular DOIs, or common assertions), consider checking for duplicates before creating a new one. DOIs are case-insensitive but the nanopub network treats different cases as separate URIs.
- Always validate a TriG file with `check` before signing to catch structural errors early.
- **`npx:hasNanopubType`** can be set explicitly in pubinfo, but it is not necessary if it can be inferred — e.g. from the types of introduced (`npx:introduces`) or embedded (`npx:embeds`) resources. See [nanosession 8 slides](https://github.com/knowledgepixels/slides/blob/main/nanosession8-typeslabels/slides.md) for the full type/label determination rules.
- **Superseding referenced nanopubs**: When superseding a query template that other nanopubs reference (e.g. a view's `gen:hasViewQuery`), also supersede those referencing nanopubs so they point to the new query version.
- **One predicate per statement in templates**: Each template statement should use only one predicate for a given piece of information. Do not duplicate the same value under multiple predicates (e.g. don't use both `schema:name` and `rdfs:label` for the same title). When in doubt, prefer `rdfs:label` as the default predicate for labels/titles.
- **Use `nt:AgentPlaceholder` for people/agents in templates**: When a template field refers to a person, user, or agent (e.g. author, presenter, creator), always use `nt:AgentPlaceholder` rather than `nt:ExternalUriPlaceholder`. This provides proper agent lookup and selection in the UI.
- **Use `nt:hasDatatype` for dates in templates**: For date fields, use `nt:LiteralPlaceholder` with `nt:hasDatatype xsd:date` (date only) or `nt:hasDatatype xsd:dateTime` (date and time). This renders a date picker in the UI instead of a free-text field. No regex is needed.
- **`nt:CREATOR` as default value**: For agent/person fields where the current user is the most likely value (e.g. presenter, author), use `nt:hasDefaultValue nt:CREATOR` to pre-fill with the logged-in user. Useful for templates where the creator is typically the subject.
