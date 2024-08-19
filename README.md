# cometbft-load-test

`cometbft-load-test` is a **framework** for load testing
[CometBFT](https://cometbft.com/)-based networks, forked from
[tm-load-test](https://github.com/informalsystems/tm-load-test).

The structure/format of transactions sent to a CometBFT-based network are
specific to the ABCI application running on that network, so while
`cometbft-load-test` comes with built-in support for the `kvstore` ABCI
application (as an example), you have to build your own clients for your own
apps.

## Requirements

`cometbft-load-test` is currently tested using Go v1.22 and CometBFT v0.38.

## Usage

### Step 1: Create your project

You have to create your own load testing tool for your own ABCI application by
importing the `cometbft-load-test` package into a new project.

```bash
mkdir -p /your/project/
cd /your/project
go mod init github.com/you/my-load-tester
```

### Step 2: Create your transaction generator

Create a client that generates transactions for your ABCI app. For an example,
you can look at the [kvstore client code](./pkg/loadtest/client_kvstore.go). Put
this in `./pkg/myabciapp/client.go`

```go
package myabciapp

import "github.com/cometbft/cometbft-load-test/pkg/loadtest"

// MyABCIAppClientFactory creates instances of MyABCIAppClient
type MyABCIAppClientFactory struct {}

// MyABCIAppClientFactory implements loadtest.ClientFactory
var _ loadtest.ClientFactory = (*MyABCIAppClientFactory)(nil)

// MyABCIAppClient is responsible for generating transactions. Only one client
// will be created per connection to the remote CometBFT RPC endpoint, and
// each client will be responsible for maintaining its own state in a
// thread-safe manner.
type MyABCIAppClient struct {}

// MyABCIAppClient implements loadtest.Client
var _ loadtest.Client = (*MyABCIAppClient)(nil)

func (f *MyABCIAppClientFactory) ValidateConfig(cfg loadtest.Config) error {
    // Do any checks here that you need to ensure that the load test
    // configuration is compatible with your client.
    return nil
}

func (f *MyABCIAppClientFactory) NewClient(cfg loadtest.Config) (loadtest.Client, error) {
    return &MyABCIAppClient{}, nil
}

// GenerateTx must return the raw bytes that make up the transaction for your
// ABCI app. The conversion to base64 will automatically be handled by the
// loadtest package, so don't worry about that. Only return an error here if you
// want to completely fail the entire load test operation.
func (c *MyABCIAppClient) GenerateTx() ([]byte, error) {
    return []byte("this is my transaction"), nil
}
```

### Step 3: Create your CLI

Create your own CLI in `./cmd/my-load-tester/main.go`:

```go
package main

import (
    "github.com/cometbft/cometbft-load-test/pkg/loadtest"
    "github.com/you/my-load-tester/pkg/myabciapp"
)

func main() {
    if err := loadtest.RegisterClientFactory("my-abci-app-name", &myabciapp.MyABCIAppClientFactory{}); err != nil {
        panic(err)
    }
    // The loadtest.Run method will handle CLI argument parsing, errors,
    // configuration, instantiating the load test and/or coordinator/worker
    // operations, etc. All it needs is to know which client factory to use for
    // its load testing.
    loadtest.Run(&loadtest.CLIConfig{
        AppName:              "my-load-tester",
        AppShortDesc:         "Load testing application for My ABCI App",
        AppLongDesc:          "Some long description on how to use the tool",
        DefaultClientFactory: "my-abci-app-name",
    })
}
```

For an example of very simple integration testing, you could do something
similar to what's covered in
[integration\_test.go](./pkg/loadtest/integration_test.go).

### Step 4: Build your CLI

Then build the executable:

```bash
go build -o ./build/my-load-tester ./cmd/my-load-tester/main.go
```

## Running your load testing tool

A `cometbft-load-test`-based load testing application can be executed in one of
two modes: **standalone**, or **coordinator/worker**.

NB: In all of the following examples, replace `cometbft-load-test` with the name
of your load testing application you have built (e.g. `my-load-tester`).

### Standalone Mode

In standalone mode, `cometbft-load-test` simply broadcasts transactions to a
single endpoint from a single binary:

```bash
cometbft-load-test -c 1 -T 10 -r 1000 -s 250 \
    --broadcast-tx-method async \
    --endpoints ws://cmt-endpoint1.somewhere.com:26657/websocket,ws://cmt-endpoint2.somewhere.com:26657/websocket
```

To see a description of what all of the parameters mean, simply run:

```bash
cometbft-load-test --help
```

### Coordinator/Worker Mode

In coordinator/worker mode, which is best used for large-scale, distributed load
testing, `cometbft-load-test` allows you to have multiple worker machines
connect to a single coordinator to obtain their configuration and coordinate
their operation.

The coordinator acts as a simple WebSockets host, and the workers are WebSockets
clients.

On the coordinator machine:

```bash
# Run cometbft-load-test with similar parameters to the standalone mode, but now
# specifying the number of workers to expect (--expect-workers) and the host:port
# to which to bind (--bind) and listen for incoming worker requests.
cometbft-load-test \
    coordinator \
    --expect-workers 2 \
    --bind localhost:26670 \
    -c 1 -T 10 -r 1000 -s 250 \
    --broadcast-tx-method async \
    --endpoints ws://cmt-endpoint1.somewhere.com:26657/websocket,ws://cmt-endpoint2.somewhere.com:26657/websocket
```

On each worker machine:

```bash
# Just tell the worker where to find the coordinator - it will figure out the rest.
cometbft-load-test worker --coordinator localhost:26680
```

For more help, see the command line parameters' descriptions:

```bash
cometbft-load-test coordinator --help
cometbft-load-test worker --help
```

### Endpoint Selection Strategies

An endpoint selection strategy can now be given to `cometbft-load-test` as a
parameter (`--endpoint-select-method`) to control the way in which endpoints are
selected for load testing. There are several options:

1. `supplied` (the default) - only use the supplied endpoints (via the
   `--endpoints` parameter) to submit transactions.
2. `discovered` - only use endpoints discovered through the supplied endpoints
   (by way of crawling the CometBFT peers' network info), but do not use any of
   the supplied endpoints.
3. `any` - use both the supplied and discovered endpoints to perform load
   testing.

**NOTE**: These selection strategies only apply if, and only if, the
`--expect-peers` parameter is supplied and is non-zero. The default behaviour if
`--expect-peers` is not supplied is effectively the `supplied` endpoint
selection strategy.

### Minimum Peer Connectivity

`cometbft-load-test` can wait for a minimum level of P2P connectivity before
starting the load testing. By using the `--min-peer-connectivity` command line
switch, along with `--expect-peers`, one can restrict this.

What this does under the hood is that it checks how many peers are in each
queried peer's address book, and for all reachable peers it checks what the
minimum address book size is. Once the minimum address book size reaches the
configured value, the load testing can begin.

## Monitoring

`cometbft-load-test` exposes a number of Prometheus metrics when in
coordinator/worker mode, but only from the coordinator's web server at the
`/metrics` endpoint. So if you bind your coordinator node to `localhost:26670`,
you should be able to get these metrics from:

```bash
curl http://localhost:26670/metrics
```

The following kinds of metrics are made available here:

* Total number of transactions recorded from the coordinator's perspective
  (across all workers)
* Total number of transactions sent by each worker
* The status of the coordinator node, which is a gauge that indicates one of the
  following codes:
  * 0 = Coordinator starting
  * 1 = Coordinator waiting for all peers to connect
  * 2 = Coordinator waiting for all workers to connect
  * 3 = Load test underway
  * 4 = Coordinator and/or one or more worker(s) failed
  * 5 = All workers completed load testing successfully
* The status of each worker node, which is also a gauge that indicates one of
  the following codes:
  * 0 = Worker connected
  * 1 = Worker accepted
  * 2 = Worker rejected
  * 3 = Load testing underway
  * 4 = Worker failed
  * 5 = Worker completed load testing successfully
* Standard Prometheus-provided metrics about the garbage collector in
  `cometbft-load-test`
* The ID of the load test currently underway (defaults to 0), set by way of the
  `--load-test-id` flag on the coordinator

## Aggregate Statistics

You can write simple aggregate statistics to a CSV file once testing completes
by specifying the `--stats-output` flag:

```bash
# In standalone mode
cometbft-load-test -c 1 -T 10 -r 1000 -s 250 \
    --broadcast-tx-method async \
    --endpoints ws://cmt-endpoint1.somewhere.com:26657/websocket,ws://cmt-endpoint2.somewhere.com:26657/websocket \
    --stats-output /path/to/save/stats.csv

# From the coordinator in coordinator/worker mode
cometbft-load-test \
    coordinator \
    --expect-workers 2 \
    --bind localhost:26670 \
    -c 1 -T 10 -r 1000 -s 250 \
    --broadcast-tx-method async \
    --endpoints ws://cmt-endpoint1.somewhere.com:26657/websocket,ws://cmt-endpoint2.somewhere.com:26657/websocket \
    --stats-output /path/to/save/stats.csv
```

The output CSV file has the following format at present:

```csv
Parameter,Value,Units
total_time,10.002,seconds
total_txs,9000,count
avg_tx_rate,899.818398,transactions per second
```

## Development

To run the linter and the tests:

```bash
make lint
make test
```

### Integration Testing

Integration testing requires Docker to be installed locally.

```bash
make integration-test
```

This integration test:

1. Sets up a 4-validator, fully connected CometBFT-based network on a
   192.168.0.0/16 subnet (the same kind of testnet as the CometBFT localnet).
2. Executes integration tests against the network in series (it's important that
   integration tests be executed in series so as to not overlap with one
   another).
3. Tears down the 4-validator network, reporting code coverage.

## License

Copyright 2023 CometBFT team and contributors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
