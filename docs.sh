#!/usr/bin/env bash

dub fetch ddox --DRT-gcopt=parallel:0
cp ./ddox/ddox.inc.composite.dt ~/.dub/packages/ddox-*/ddox/views/ddox.inc.composite.dt
cp ./ddox/ddox.module.dt ~/.dub/packages/ddox-*/ddox/views/ddox.module.dt

parser=~/.dub/packages/ddox-*/ddox/source/ddox/parsers/jsonparser.d
size=$(wc -c < $parser)
origSize=25965

if [ $size -eq $origSize ]
then
    patch $parser ./ddox/jsonparser.diff
fi

dub build -b ddox -c ddox --DRT-gcopt=parallel:0
cp ./ddox/ddox.css ./docs/styles/ddox.css
cp ./ddox/prettify.css ./docs/prettify/prettify.css
