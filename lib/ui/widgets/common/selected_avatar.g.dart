// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'selected_avatar.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Every avatar image (SVG, PNG, JPG or WebP) currently bundled under
/// [avatarAssetDir] (filenames only), discovered from Flutter's asset
/// manifest instead of a hardcoded list - adding or removing a file from
/// that folder (pubspec.yaml already bundles the whole avatars/ folder)
/// just needs a rebuild, nothing here. Default avatar always sorts first.

@ProviderFor(avatarAssets)
final avatarAssetsProvider = AvatarAssetsProvider._();

/// Every avatar image (SVG, PNG, JPG or WebP) currently bundled under
/// [avatarAssetDir] (filenames only), discovered from Flutter's asset
/// manifest instead of a hardcoded list - adding or removing a file from
/// that folder (pubspec.yaml already bundles the whole avatars/ folder)
/// just needs a rebuild, nothing here. Default avatar always sorts first.

final class AvatarAssetsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<String>>,
          List<String>,
          FutureOr<List<String>>
        >
    with $FutureModifier<List<String>>, $FutureProvider<List<String>> {
  /// Every avatar image (SVG, PNG, JPG or WebP) currently bundled under
  /// [avatarAssetDir] (filenames only), discovered from Flutter's asset
  /// manifest instead of a hardcoded list - adding or removing a file from
  /// that folder (pubspec.yaml already bundles the whole avatars/ folder)
  /// just needs a rebuild, nothing here. Default avatar always sorts first.
  AvatarAssetsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'avatarAssetsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$avatarAssetsHash();

  @$internal
  @override
  $FutureProviderElement<List<String>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<String>> create(Ref ref) {
    return avatarAssets(ref);
  }
}

String _$avatarAssetsHash() => r'416140f960bc7f8a760cbc458558560c9554c7cb';
