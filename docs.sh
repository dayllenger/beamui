#!/usr/bin/env bash

dub fetch ddox
cp ./ddox/ddox.inc.composite.dt ~/.dub/packages/ddox-*/ddox/views/ddox.inc.composite.dt
cp ./ddox/ddox.module.dt ~/.dub/packages/ddox-*/ddox/views/ddox.module.dt
dub build -b ddox
cp ./ddox/ddox.css ./docs/styles/ddox.css
cp ./ddox/prettify.css ./docs/prettify/prettify.css
