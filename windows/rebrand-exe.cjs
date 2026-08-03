#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const { NtExecutable, NtExecutableResource } = require("pe-library");
const { load } = require("resedit/cjs");

async function main() {
  const [sourcePath, iconPath, outputPath] = process.argv.slice(2);
  if (!sourcePath || !iconPath || !outputPath) {
    throw new Error("Usage: rebrand-exe.cjs <source.exe> <icon.ico> <output.exe>");
  }

  const ResEdit = await load();
  const executable = NtExecutable.from(fs.readFileSync(sourcePath), { ignoreCert: true });
  const resources = NtExecutableResource.from(executable);
  const iconFile = ResEdit.Data.IconFile.from(fs.readFileSync(iconPath));
  const iconGroups = ResEdit.Resource.IconGroupEntry.fromEntries(resources.entries);
  const groups = iconGroups.length ? iconGroups : [{ id: 1, lang: 1033 }];

  for (const group of groups) {
    ResEdit.Resource.IconGroupEntry.replaceIconsForResource(
      resources.entries,
      group.id,
      group.lang,
      iconFile.icons.map((item) => item.data),
    );
  }

  for (const versionInfo of ResEdit.Resource.VersionInfo.fromEntries(resources.entries)) {
    versionInfo.setFileVersion(0, 4, 1, 0, 1033);
    versionInfo.setProductVersion(0, 4, 1, 0, 1033);
    const languages = versionInfo.getAllLanguagesForStringValues();
    const targets = languages.length ? languages : [{ lang: 1033, codepage: 1200 }];
    for (const language of targets) {
      versionInfo.setStringValues(language, {
        CompanyName: "Stock Pet",
        FileDescription: "Stock Pet 桌面行情宠物",
        InternalName: "StockPet",
        OriginalFilename: "StockPet.exe",
        ProductName: "Stock Pet",
      });
    }
    versionInfo.outputToResourceEntries(resources.entries);
  }

  resources.outputResource(executable);
  fs.writeFileSync(outputPath, Buffer.from(executable.generate()));
  console.log(`Rebranded ${outputPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
