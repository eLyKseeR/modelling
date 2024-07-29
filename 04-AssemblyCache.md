# AssemblyCache

An assembly cache manages a list of readable [environments](./02-Assemblies.md#environment) and a single writable [environment](./02-Assemblies.md#environment). The first ones represent the recalled assemblies which form the cache. Any write attempt to the cache will fill in the current writable environment and its assembly, and as soon as this is full it will be encrypted and extracted to chunks. A fresh assembly is then created in the writable environment.

![AssemblyCache model](./out/services.uml/assemblycache/assemblycache%20modules.png)

The _AssemblyCache_ has access to [_KeyListStore_](./01-DataStore.md#keyliststore), [_FileinformationStore_](./01-DataStore.md#fileinformationstore), and [_FBlockListStore_](./01-DataStore.md#fblockliststore) for requesting encryption keys or depositing new ones, or adding file information and blocks as they are written or read.

Internally, the _AssemblyCache_ manages two queues, one for writing blocks and one for reading blocks.

## Write operation

![AssemblyCache write operation](./out/services.uml/assemblycache/asssemblycache%20write%20usage.png)

* initialisation of the assembly cache
* repeating enqueueing of write requests
   * when the assembly is full, then it's encrypted and extracted to chunks
* at the end, the assembly cache is flushed and the currently open _EnvironmentWritable_'s assembly encrypted and extracted to chunks.

## Read operation

![AssemblyCache read operation](./out/services.uml/assemblycache/asssemblycache%20read%20usage.png)

* initialisation of the assembly cache
* repeating enqueueing of read requests
   * when the queue is full, then the requests are executed in batches
   * ensure the assembly is loaded: either in the cache, or needs recall from chunks
   * read the requested blocks from the assembly, probably in parallel
* at the end, the assembly cache is simply closed and its resources released
