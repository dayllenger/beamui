/**
This module contains UI internationalization support implementation.

UIString struct provides string container which can be either plain unicode string or id of string resource.

Translation strings are being stored in translation files, consisting of simple key=value pair lines:
---
STRING_RESOURCE_ID=Translation text 1
ANOTHER_STRING_RESOURCE_ID=Translation text 2
---

Supports fallback to another translation file (e.g. default language).

If string resource is not found neither in main nor fallback translation files, UNTRANSLATED: RESOURCE_ID will be returned.

String resources must be placed in i18n subdirectory inside one or more resource directories (set using platform.resourceDirs
property on application initialization).

File names must be language code with extension .ini (e.g. en.ini, fr.ini, es.ini)

If several files for the same language are found in (different directories) their content will be merged. It's useful to merge string resources
from beamui framework with resources of application.

Set interface language using platform.uiLanguage in UIAppMain during initialization of application settings:
---
platform.uiLanguage = "en";

/// Create by id - string STR_MENU_HELP="Help" must be added to translation resources
UIString help1 = UIString.fromID("STR_MENU_HELP");
/// Create by id and fallback string
UIString help2 = UIString.fromID("STR_MENU_HELP", "Help"d);
/// Create from raw string
UIString help3 = UIString.fromRaw("Help"d);

---


Synopsis:
---
import beamui.core.i18n;

// use global i18n object to get translation for string ID
dstring translated = i18n.get("STR_FILE_OPEN");
// as well, you can specify fallback value - to return if translation is not found
dstring translated = i18n.get("STR_FILE_OPEN", "Open..."d);

// UIString type can hold either string resource id or dstring raw value.
UIString text;

// assign resource id as string (will remove dstring value if it was here)
text = "ID_FILE_EXIT";
// or assign raw value as dstring (will remove id if it was here)
text = "some text"d;
// assign both resource id and fallback value - to use if string resource is not found
text = UIString("ID_FILE_EXIT", "Exit"d);

// i18n.get() will automatically be invoked when getting UIString value (e.g. using alias this).
dstring translated = text;
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.core.i18n;

import mofile;
import beamui.core.functions;
import beamui.core.logger;
import beamui.graphics.resources;

/// Translate a message to current application language
dstring tr(string original)
{
    string translated = original;
    foreach (tr; translators)
    {
        translated = tr.gettext(original);
        if (translated != original)
            break;
    }
    return translated.toUTF32;
}

/// ditto
dstring tr(dstring original)
{
    return tr(original.toUTF8);
}

/// Load translations for language from .mo file
void loadTranslator(string lang)
{
    auto filename = resourceList.getPathByID(lang ~ ".mo");
    if (filename)
    {
        auto content = loadResourceBytes(filename);
        translators ~= new MoFile(cast(immutable void[])content);
    }
}

private MoFile*[] translators;
