# AssemblyCache

An assembly cache manages a list of readable [environments](./02-Assemblies.md#environment) and a single writable [environment](./02-Assemblies.md#environment). The first ones represent the recalled assemblies which form the cache. Any write attempt to the cache will fill in the current writable environment and its assembly, and as soon as this is full it will be encrypted and extracted to chunks. A fresh assembly is then created in the writable environment.

![AssemblyCache model](./out/services.uml/assemblycache/assemblycache%20modules.png)

The _AssemblyCache_ has access to [_KeyListStore_](./01-DataStore.md#keyliststore), [_FileinformationStore_](./01-DataStore.md#fileinformationstore), and [_FBlockListStore_](./01-DataStore.md#fblockliststore) for requesting encryption keys or depositing new ones, or adding file information and blocks as they are written or read.

Internally, the _AssemblyCache_ manages two queues, one for writing blocks and one for reading blocks. Both are bounded (`qsize` = 12): `enqueue_write_request()` and `enqueue_read_request()` return `false` when the queue is full, and the client must then run the queue (`iterate_write_queue()` / `iterate_read_queue()`) and enqueue again. This is what the [Processor](./05-Processor.md) does.

Entries of the queues:

| queue | entry | fields |
|---|---|---|
| write | `writequeueentity` | `qfhash` (file), `qfpos` (position in file), `qbuffer` (data; its size is the block size) |
| read | `readqueueentity` | `rqaid` (assembly), `rqapos` (position in assembly), `rqrlen` (length), `rqfpos` (position in file), `rqchecksum` (checksum of the block from the meta data, `""` = unknown) |
| read result | `readqueueresult` | `readrequest`, `rresult` (data) |

![AssemblyCache components](./out/services.uml/assemblycache/assemblycache%20components.png)

## Write operation

![AssemblyCache write operation](./out/services.uml/assemblycache/assemblycache%20write%20usage.png)

* initialisation of the assembly cache
* repeating enqueueing of write requests
   * when the queue is full, then the queue is run: each block is backed up into the _EnvironmentWritable_ and its block information added to the _FBlockListStore_
   * when the assembly is full, then it's encrypted and extracted to chunks, and its key added to the _KeyListStore_
* at the end, the queue is run once more and the assembly cache closed (`close()`): the currently open _EnvironmentWritable_'s assembly is encrypted and extracted to chunks. (`flush()` does the same, but continues with a fresh writable assembly.)

File meta data is added with `add_fileinformation()`, and block meta data of unchanged blocks with `add_fileblockinformation()`.

## Read operation

![AssemblyCache read operation](./out/services.uml/assemblycache/assemblycache%20read%20usage.png)

* initialisation of the assembly cache
* repeating enqueueing of read requests
   * when the queue is full, then the requests are executed (`iterate_read_queue()`)
   * ensure the assembly is loaded: either in the cache (then moved to the head of the list), or it is recalled from chunks with the key from the _KeyListStore_. The cache holds at most `acsize` readable environments; the least recently used one is dropped.
   * read the requested block from the assembly; if the request carries a checksum, the block is verified against it, and a block that does not match is not returned
* at the end, the queue is run once more
