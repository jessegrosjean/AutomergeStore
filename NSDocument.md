#  NSDocument Notes

By default this is "shoebox" style storage, files written to your application container.

Question: how to integrate this with NSDocument if you would like to use that application model instead?

Thoughts:

- Based of Workspace model (so N Automerge.Document with one special index document)
- Not based on AutomergeStore, instead uses file wrapper storage
- Each document is stored as data (no incremental) with UUID filename.
- Also includes metadata plist in wrapper, which stores index UUID
The "magic" part:
    - When loads document it looks at existing AutomergeStore and looks for matching document (that is being synced to icloude). It merges in any changes and then uses AutomergeStore's Automerge.Document instance.
    - So NSDocument is not dependent on AutomergeStore state, but if it finds matching state then it will use that state and automatically sync.
