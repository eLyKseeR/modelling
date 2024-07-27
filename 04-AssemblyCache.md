# AssemblyCache

An assembly cache manages a list of readable [environments](./02-Assemblies.md#environment) and a single writable [environment](./02-Assemblies.md#environment). The first ones represent the recalled assemblies which form the cache. Any write attempt to the cache will fill in the current writable environment and its assembly, and as soon as this is full it will be encrypted and extracted to chunks. A fresh assembly is then created in the writable environment.

![AssemblyCache model](./out/services.uml/assemblycache/assemblycache%20modules.png)

The _AssemblyCache_ has access to _KeyListStore_ and _FBlockListStore_ for requesting encryption keys or depositing new ones, or adding file blocks as they are written or read.

Internally, the _AssemblyCache_ manages two queues, one for writing blocks and one for reading blocks.
