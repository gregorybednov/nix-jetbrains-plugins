{
  lib,
  fetchurl,
  fetchzip,
  stdenv,
}:
with builtins;
with lib;
let
  SEPARATOR = "/--/";

  fetchPluginSrc =
    { url, hash }:
    let
      isJar = hasSuffix ".jar" url;
      fetcher = if isJar then fetchurl else fetchzip;
    in
    fetcher {
      executable = isJar;
      inherit url hash;
    };

  downloadPlugin =
    {
      name,
      version,
      url,
      hash,
    }:
    let
      isJar = hasSuffix ".jar" url;
      installPhase =
        if isJar then
          ''
            runHook preInstall
            mkdir -p $out && cp $src $out
            runHook postInstall
          ''
        else
          ''
            runHook preInstall
            mkdir -p $out && cp -r . $out
            runHook postInstall
          '';
    in
    stdenv.mkDerivation {
      inherit name version;
      src = fetchPluginSrc { inherit url hash; };
      dontUnpack = isJar;
      inherit installPhase;
    };

  readGeneratedDir = attrNames (
    filterAttrs (name: _: hasSuffix ".json" name) (readDir ./generated/ides)
  );

  # Folds into the set of { IDENAME = { VERSION = [ x y ]; }; }
  buildIdeVersionMap = (
    accu: value:
    accu
    // {
      "${value.version}" = (accu."${value.version}" or { }) // value.value;
    }
  );

  # Find and construct plugin from a list of plugins
  findPlugin =
    pluginList: name: version:
    let
      key = "${name}${SEPARATOR}${version}";
      match = pluginList."${key}";
    in
    {
      inherit name version;
      url = "https://downloads.marketplace.jetbrains.com/${match.p}";
      hash = "sha256-${match.h}";
    };

  allPlugins = fromJSON (readFile ./generated/all_plugins.json);
in
(groupBy' buildIdeVersionMap { } (x: x.ideName) (
  map (
    jsonFile:
    let
      # Split the JSON filename into IDENAME-VERSION and remove json suffix
      parts = splitString "-" (removeSuffix ".json" jsonFile);
    in
    {
      ideName = concatStrings (intersperse "-" (init parts));
      version = elemAt parts ((length parts) - 1);
      value = mapAttrs (k: v: downloadPlugin (findPlugin allPlugins k v)) (
        fromJSON (readFile (./generated/ides + "/${jsonFile}"))
      );
    }
  ) readGeneratedDir
))