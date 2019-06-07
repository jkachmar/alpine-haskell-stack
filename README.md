# GHC, Alpine, Stack, and Docker

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [Prerequisites](#prerequisites)
- [Building the Docker Images](#building-the-docker-images)
    - ["Quick" Start](#quick-start)
    - [Overview](#overview)
- [Developing Locally with `stack`](#developing-locally-with-stack)
- [TODO](#todo)

<!-- markdown-toc end -->

This repository is a small demonstration of the steps required to build an 
Alpine Linux Docker image with all the tools necessary to compile Haskell
programs linked against `musl` libc.

Such an environment are extremely useful for producing small Docker images for
the deployment of services and for creating portable Haskell executables (either
statically linked, or bundled with the `musl` linker and their dynamic 
dependencies).

At the time of writing, this repository is primarily geared towards showing off
a workflow by which one can use `stack`'s Docker integration to seamlessly 
develop inside an Alpine Linux container. This gives the benefit of `stack`'s
build caching and also integrates nicely with development tools like `ghcid`.

In the future I hope to either update this repository with explicit instructions
and/or examples that show how one can create minimal (i.e. tens of MB) 
Docker images to deploy Haskell applications in production.

## Prerequisites

Ensure Docker is installed on your computer and the Docker daemon is running.

Install the [Haskell Tool Stack](https://docs.haskellstack.org/en/stable/README/).

## Building the Docker Images

At the time of writing (1 Apr. 2019) GHC-HQ doesn't provide a version of GHC 
that is compatible with `musl` libc, and the `ghc` package provided by Alpine
is out of date. 

This means that the first step in this process is going to be _compiling GHC
itself_ and packaging up all the necessary tools and dependencies in an Alpine 
Linux container.

For convenience, I've combined all of these steps into a single, multi-stage
[Dockerfile](Dockerfile) in this repository, and written a [Makefile](Makefile)
that caches the intermediate build layers so changes to the final environment
don't trigger a full rebuild of GHC and the associated tooling.

### "Quick" Start

To build the Docker images, navigate to the project root directory and run:

    make docker-build-gmp

Keep in mind that this stage compiles GHC, which can take anywhere from 30 mins
to upwards of an hour depending on how fast your computer is.

### Overview

I've tried to keep the [Dockerfile](Dockerfile) relatively well commented, but
the build process can be roughly understood as an impl

- `base`
  - Base layer used for all the intermediate build images to follow
  - Uses a patched version of the [ghcup](https://github.com/haskell/ghcup/)
  build script
    - [The patch](docker/ghcup.diff) is used to override `ghcup`'s' 
    configuration stage to use the `gold` linker, which Alpine requires
  - Contains all OS dependencies required to run `ghcup` and `stack`

- `build-ghc`
  - Builds GHC via `ghcup`
  - Contains all dependencies required to build GHC
  - Contains some (currently unused) logic for selecting between `integer-gmp`
  and `integer-simple`
    - `integer-gmp` depends on `libgmp`, which is licensed under the LGPL, so
    if one wants to distribute a statically linked, closed source binary they
    will need to build against a version of GHC that uses `integer-simple`

- `build-tooling`
  - Downloads `stack` and verifies the hash

- `alpine-haskell`
  - Assembles artifacts from the previous layers
  - Copies GHC and `stack`
  - Installs `bash` and `shadow`
    - `stack` requires `usermod`/`groupmod` from `shadow` as well as `bash` to
    run
    
## Developing Locally with `stack`

Once the images have finished building, this project can be compiled to 
demonstrate what local development looks like with `stack`.

For convenience, I've added some targets to the [Makefile](Makefile) that run
some common development tasks.

First, ensure that `ghcid` is installed (for example, by running 
`stack build --copy-compiler-tool ghcid`).

Then, compile this project in Docker by running `make build-fast`.

Finally, start a `ghcid` development loop with `make ghcid`; this loop uses
`stack --docker` to spawn a container in which GHC recompiles everything 
whenever it detects changes in your code.

Try changing something in `executables/Main.hs` and see the changes reflected in
`ghcid`!

## TODO

- Demonstrate `integer-simple` support
- Demonstrate static linking
- Create separate `Dockerfile`s for GHC and combined tooling
  - Automate the creation of these images in CI and host them on Dockerhub

## Related work

- [build most Haskell programs into fully static Linux executables using Nix](https://github.com/nh2/static-haskell-nix)
