# exobooks

A ledger system of record for bookkeeping agents: the books live in exobooks, and the
bookkeeping intelligence is your own AI agent, working them from outside.

**Status: nothing to use yet.** This repository currently holds one thing, a hello-world jar
that checks whether a machine or an agent workspace can run exobooks at all. If you are an
agent that was asked to try this repository out, the section below is for you.

## For agents: the compatibility check

The goal is to find out whether exobooks can run in the environment you are working in, and
to tell the person who asked what happened. A failure is a useful result. Please report it
rather than working around it silently.

This checks one way of running exobooks: as a jar, on Java 26. That is the version exobooks is
developed and tested on.

The jar depends on Clojure and on [sqlite4clj](https://github.com/andersmurphy/sqlite4clj), which carries SQLite built for macOS, Linux and Windows.

### 1. Find or install Java 26

```sh
java -version
```

If that prints version 26, use it and skip to step 2. Otherwise install a private copy into the
current directory. This needs no root and no package manager, and leaves any other Java alone:

```sh
os=$(uname -s | sed 's/Darwin/mac/; s/Linux/linux/')
cpu=$(uname -m | sed 's/arm64/aarch64/; s/x86_64/x64/')
release=https://github.com/adoptium/temurin26-binaries/releases/download/jdk-26.0.2.1%2B1
url="$release/OpenJDK26U-jre_${cpu}_${os}_hotspot_26.0.2.1_1.tar.gz"
mkdir -p java26 && curl -fsSL "$url" | tar -xz -C java26 --strip-components=1
```

That is Eclipse Temurin 26, an open-source build of Java at `java26/bin/java` on Linux and `java26/Contents/Home/bin/java` on a Mac.  Use that path wherever the steps below say `java`.

### 2. Download exobooks.jar

```sh
curl -fL -o exobooks.jar https://github.com/exobooks/exobooks/releases/latest/download/exobooks.jar
```

### 3. Run it

```sh
java -jar exobooks.jar
```

Success looks something like this (depending on your OS):

```
hello world
java:    26.0.2.1 Eclipse Adoptium at /path/to/java26/Contents/Home
os:      Mac OS X 27.0.1 aarch64
heap:    30688 MB max
sqlite:  3.51.3 (bundled, loaded through the FFM API); 1+...+10 = 55
OK: Java 26 and the bundled SQLite both work here.
```

### 4. Report back

Tell the person who asked whether it succeeded, and if not, why it failed.  Maybe you can help them figure out how to get it working.
