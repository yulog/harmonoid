/// This file is a part of Harmonoid (https://github.com/harmonoid/harmonoid).
///
/// Copyright © 2020-2022, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
///
/// Use of this source code is governed by the End-User License Agreement for Harmonoid that can be found in the EULA.txt file.
///

import 'dart:io';
import 'dart:collection';
import 'dart:convert' as convert;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:libmpv/libmpv.dart' hide Playlist, Media;
import 'package:libmpv/libmpv.dart' as libmpv;
import 'package:path/path.dart' as path;
import 'package:flutter_media_metadata/flutter_media_metadata.dart';

import 'package:harmonoid/models/media.dart';
import 'package:harmonoid/utils/file_system.dart';
import 'package:harmonoid/utils/safe_session_storage.dart';

/// Collection
/// ----------
///
/// Primary music collection generator & indexer of [Harmonoid](https://github.com/harmonoid/harmonoid).
///
class Collection extends ChangeNotifier {
  /// [Collection] object instance. Must call [Collection.initialize].
  static late Collection instance = Collection();

  /// Initializes the music collection.
  ///
  /// Called before [runApp] & is non-blocking, [refresh] is used for indexing the music.
  ///
  static Future<void> initialize({
    required List<Directory> collectionDirectories,
    required Directory cacheDirectory,
    required CollectionSort collectionSortType,
    required CollectionOrder collectionOrderType,
  }) async {
    instance.collectionDirectories = collectionDirectories;
    instance.cacheDirectory = cacheDirectory;
    instance.collectionSortType = collectionSortType;
    instance.collectionOrderType = collectionOrderType;
    instance.albumArtDirectory = Directory(
        path.join(instance.cacheDirectory.path, kAlbumArtsDirectoryName));
    instance.unknownAlbumArt = File(path.join(cacheDirectory.path,
        kAlbumArtsDirectoryName, kUnknownAlbumArtFileName));
    for (Directory directory in collectionDirectories) {
      if (!await directory.exists_()) await directory.create_();
    }
    if (!await instance.unknownAlbumArt.exists_()) {
      await instance.unknownAlbumArt.create_();
      await instance.unknownAlbumArt.writeAsBytes(
          (await rootBundle.load(kUnknownAlbumArtRootBundle))
              .buffer
              .asUint8List());
    }
  }

  List<Album> albums = [];
  List<Track> tracks = [];
  List<Artist> artists = [];
  List<Playlist> playlists = <Playlist>[];
  HashSet<Album> get albumsSet => _albums;
  HashSet<Track> get tracksSet => _tracks;
  HashSet<Artist> get artistsSet => _artists;

  late List<Directory> collectionDirectories;
  late Directory cacheDirectory;
  late CollectionSort collectionSortType;
  late CollectionOrder collectionOrderType;
  late Directory albumArtDirectory;
  late File unknownAlbumArt;

  SplayTreeMap<AlbumArtist, HashSet<Album>> albumArtists =
      SplayTreeMap<AlbumArtist, HashSet<Album>>();

  /// Adds new directories that will be used for indexing of the music.
  ///
  Future<void> addDirectories({
    required List<Directory> directories,
    void Function(int?, int, bool)? onProgress,
  }) async {
    final directory = <File>[];
    this.collectionDirectories.addAll(directories);
    onProgress?.call(null, directory.length, false);
    // Basically [Collection.index] the newly added directories, a lot more efficient.
    for (final collectionDirectory in directories) {
      directory.addAll(
          await (collectionDirectory.list_(extensions: kSupportedFileTypes)));
    }
    for (int index = 0; index < directory.length; index++) {
      final object = directory[index];
      try {
        final metadata = <String, dynamic>{
          'uri': object.uri.toString(),
        };
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          try {
            metadata.addAll(await tagger.parse(
              libmpv.Media(object.uri.toString()),
              coverDirectory: albumArtDirectory,
              timeout: Duration(seconds: 2),
            ));
          } catch (exception, stacktrace) {
            debugPrint(exception.toString());
            debugPrint(stacktrace.toString());
          }
          final track = Track.fromTagger(metadata);
          await _arrange(track);
        } else {
          final _metadata = await MetadataRetriever.fromUri(
            object.uri,
            coverDirectory: albumArtDirectory,
          );
          metadata.addAll(_metadata.toJson().cast());
          final track = Track.fromJson(metadata);
          await _arrange(track);
        }
      } catch (exception, stacktrace) {
        debugPrint(exception.toString());
        debugPrint(stacktrace.toString());
      }
      try {
        onProgress?.call(index + 1, directory.length, false);
      } catch (exception) {}
    }
    await _arrangeArtists(notifyListeners: false);
    await sort(notifyListeners: false);
    await saveToCache();
    try {
      onProgress?.call(directory.length, directory.length, true);
    } catch (exception) {}
    notifyListeners();
  }

  /// Removes the asked directories from the collection & will no longer be used for indexing.
  ///
  Future<void> removeDirectories({
    required List<Directory> directories,
    void Function(int?, int, bool)? onProgress,
  }) async {
    onProgress?.call(null, 0, false);
    for (final directory in [...directories]) {
      collectionDirectories.remove(directory);
    }
    final currentTracks = HashSet<Track>();
    int i = 0;
    for (final element in _tracks) {
      final track = element;
      bool present = false;
      for (final directory in collectionDirectories) {
        if (track.uri.toFilePath().startsWith(directory.path)) {
          present = true;
          break;
        }
      }
      if (present) {
        currentTracks.add(track);
      }
      try {
        onProgress?.call(i + 1, _tracks.length, i + 1 == _tracks.length);
        i++;
      } catch (_) {}
    }
    _tracks = currentTracks;
    for (final element in _albums) {
      final album = element;
      final currentTracks = HashSet<Track>();
      for (final track in album.tracks) {
        bool present = false;
        for (final directory in collectionDirectories) {
          if (track.uri.toFilePath().startsWith(directory.path)) {
            present = true;
            break;
          }
        }
        if (present) {
          currentTracks.add(track);
        }
        try {
          onProgress?.call(i + 1, _tracks.length, i + 1 == _tracks.length);
          i++;
        } catch (_) {}
      }
      album.tracks.clear();
      album.tracks.addAll(currentTracks);
    }
    _albums.removeWhere((element) => element.tracks.isEmpty);
    for (final element in _artists) {
      final artist = element;
      final currentTracks = HashSet<Track>();
      for (final track in artist.tracks) {
        bool present = false;
        for (final directory in collectionDirectories) {
          if (track.uri.toFilePath().startsWith(directory.path)) {
            present = true;
            break;
          }
        }
        if (present) {
          currentTracks.add(track);
        }
        try {
          onProgress?.call(i + 1, _tracks.length, i + 1 == _tracks.length);
          i++;
        } catch (_) {}
      }
      artist.tracks.clear();
      artist.tracks.addAll(currentTracks);
    }
    _artists.removeWhere((element) => element.tracks.isEmpty);
    try {
      onProgress?.call(_tracks.length, _tracks.length, true);
      await saveToCache();
      await sort(notifyListeners: false);
      await refresh(onProgress: onProgress);
    } catch (_) {}
    notifyListeners();
  }

  /// Searches for a [Media] based upon a the passed [query].
  ///
  List<Media> search(
    String query, {
    Media? mode,
    int? limit,
  }) {
    if (query.isEmpty) return <Media>[];
    final terms = query.toLowerCase().split(' ')
      ..removeWhere((term) => term.isEmpty);
    List<Media> result = <Media>[];
    if (mode is Album || mode == null) {
      for (final album in _albums) {
        if (terms.any((term) => album.albumName.toLowerCase().contains(term))) {
          result.add(album);
        }
      }
    }
    if (mode is Track || mode == null) {
      for (final track in _tracks) {
        if (terms.any((term) => track.trackName.toLowerCase().contains(term))) {
          result.add(track);
        }
      }
    }
    if (mode is Artist || mode == null) {
      for (final artist in _artists) {
        if (terms
            .any((term) => artist.artistName.toLowerCase().contains(term))) {
          result.add(artist);
        }
      }
    }
    return result;
  }

  /// Adds a new track to the music collection.
  ///
  /// Normally used when refreshing the music collection. Internally called by [refresh].
  ///
  Future<void> add({
    required File file,
    bool notifyListeners: true,
  }) async {
    if (kSupportedFileTypes.contains(file.extension)) {
      try {
        final metadata = <String, dynamic>{
          'uri': file.uri.toString(),
        };
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          try {
            metadata.addAll(await tagger.parse(
              libmpv.Media(file.uri.toString()),
              coverDirectory: albumArtDirectory,
              timeout: Duration(seconds: 2),
            ));
          } catch (exception, stacktrace) {
            debugPrint(exception.toString());
            debugPrint(stacktrace.toString());
          }
          final track = Track.fromTagger(metadata);
          await _arrange(
            track,
          );
          await _arrangeArtists(notifyListeners: false);
          final found =
              albumArtists[AlbumArtist(track.albumArtistName)]?.lookup(
            Album(
              albumName: track.albumName,
              year: track.year,
              albumArtistName: track.albumArtistName,
            ),
          );
          debugPrint(found.toString());
          if (found != null) {
            found.tracks.add(track);
          }
        } else {
          final _metadata = await MetadataRetriever.fromUri(
            file.uri,
            coverDirectory: albumArtDirectory,
          );
          metadata.addAll(_metadata.toJson().cast());
          final track = Track.fromJson(metadata);
          await _arrange(
            track,
          );
          await _arrangeArtists(notifyListeners: false);
          final found =
              albumArtists[AlbumArtist(track.albumArtistName)]?.lookup(
            Album(
              albumName: track.albumName,
              year: track.year,
              albumArtistName: track.albumArtistName,
            ),
          );
          debugPrint(found.toString());
          if (found != null) {
            found.tracks.add(track);
          }
        }
      } catch (exception, stacktrace) {
        debugPrint(exception.toString());
        debugPrint(stacktrace.toString());
      }
    }
    await saveToCache();
    await sort(notifyListeners: notifyListeners);
    if (notifyListeners) {
      this.notifyListeners();
    }
  }

  /// Removes a [Media] i.e. [Album], [Track] or [Artist] from the music collection.
  ///
  /// Automatically updates other structures & models. Also deletes the respective files.
  ///
  Future<void> delete(
    Media object, {
    bool delete: true,
    bool notifyListeners: true,
  }) async {
    if (object is Track) {
      _tracks.remove(object);
      for (final album in _albums) {
        if (object.albumName == album.albumName &&
            object.albumArtistName == album.albumArtistName) {
          album.tracks.remove(object);
          if (album.tracks.isEmpty) {
            _albums.remove(album);
          }
          break;
        }
      }
      for (String artistName in object.trackArtistNames) {
        try {
          final artist = _artists.lookup(Artist(artistName: artistName))!;
          artist.tracks.remove(object);
          if (artist.tracks.isEmpty) {
            _artists.remove(artist);
          } else {
            for (Album album in artist.albums) {
              if (object.albumName == album.albumName &&
                  object.albumArtistName == album.albumArtistName) {
                album.tracks.remove(object);
                break;
              }
            }
            artist.albums.removeWhere((element) => element.tracks.isEmpty);
          }
        } catch (exception, stacktrace) {
          debugPrint(exception.toString());
          debugPrint(stacktrace.toString());
        }
      }
      for (final album in albumArtists[AlbumArtist(object.albumArtistName)]!) {
        album.tracks.remove(object);
        if (album.tracks.isEmpty) {
          albumArtists[AlbumArtist(object.albumArtistName)]!.remove(album);
          break;
        }
      }
      if (albumArtists[AlbumArtist(object.albumArtistName)]!.isEmpty) {
        albumArtists.remove(AlbumArtist(object.albumArtistName));
      }
      if (delete && await File(object.uri.toFilePath()).exists_()) {
        await File(object.uri.toFilePath()).delete_();
      }
    } else if (object is Album) {
      _albums.remove(object);
      _tracks.removeWhere((track) =>
          object.albumName != track.albumName &&
          object.albumArtistName != track.albumArtistName);
      for (final artist in _artists) {
        if (artist.albums.remove(
            object) /* If album is found, then only track would be present */) {
          artist.tracks.removeWhere(
            (element) =>
                object.albumName != element.albumName &&
                object.albumArtistName != element.albumArtistName,
          );
        }
      }
      albumArtists[AlbumArtist(object.albumArtistName)]!.remove(object);
      if (albumArtists[AlbumArtist(object.albumArtistName)]!.isEmpty) {
        albumArtists.remove(AlbumArtist(object.albumArtistName));
      }
      if (delete) {
        for (Track track in object.tracks) {
          if (await File(track.uri.toFilePath()).exists_()) {
            await File(track.uri.toFilePath()).delete_();
          }
        }
      }
    }
    if (notifyListeners) {
      this.notifyListeners();
    }
    await Future.wait([sort(notifyListeners: false), saveToCache()]);
  }

  /// Saves the currently visible music collection to the cache.
  ///
  Future<void> saveToCache() async {
    await Future.wait(
      [
        _trackStorage.write(
          {
            'tracks': _tracks.map((e) => e.toJson()).toList(),
          },
        ),
        _albumStorage.write(
          {
            'albums': _albums.map((e) => e.toJson()).toList(),
          },
        ),
        _artistStorage.write(
          {
            'artists': _artists.map((e) => e.toJson()).toList(),
          },
        ),
      ],
    );
  }

  /// Refreshes the music collection.
  ///
  /// Generally expected to automatically happen in background. [onProgress] only notifies when [index] was called internally.
  /// Suitable for efficiently checking one or two newly added files or when refresh button is tapped by the user.
  ///
  /// Automatically calls [index] internally if no cache is found.
  /// Checks for newly added & deleted tracks to update the music collection.
  ///
  /// Non-blocking in nature. Sends progress updates to the optional callback parameter [onProgress].
  ///
  /// Passing [update] will also cause method to lookup for new & deleted files to update collection accordingly.
  /// Earlier, this was enabled by default.
  ///
  Future<void> refresh({
    void Function(int? completed, int total, bool isCompleted)? onProgress,
    bool update = true,
  }) async {
    onProgress?.call(null, 1 << 32, false);
    // For safety.
    if (!await cacheDirectory.exists_()) {
      await cacheDirectory.create_();
    }
    for (Directory directory in collectionDirectories) {
      if (!await directory.exists_()) {
        await directory.create_();
      }
    }
    // Clear existing indexed music.
    _albums = HashSet<Album>();
    _tracks = HashSet<Track>();
    _artists = HashSet<Artist>();
    // Indexing from scratch if no cache exists.
    if (!await File(
                path.join(cacheDirectory.path, kCollectionTrackCacheFileName))
            .exists_() &&
        !await File(
                path.join(cacheDirectory.path, kCollectionAlbumCacheFileName))
            .exists_() &&
        !await File(
                path.join(cacheDirectory.path, kCollectionArtistCacheFileName))
            .exists_()) {
      index(onProgress: onProgress);
    }
    // Just check for newly added or deleted tracks if cache exists.
    else {
      try {
        // Restore cache.
        await Future.wait(
          [
            () async {
              _tracks = await compute(
                parseTrackHashSetFromData,
                await _trackStorage.read(),
              );
            }(),
            () async {
              final result = await compute(
                parseAlbumHashSetFromData,
                await _albumStorage.read(),
              );
              _albums = result.first;
              albumArtists = result.last;
            }(),
            () async {
              _artists = await compute(
                parseArtistHashSetFromData,
                await _artistStorage.read(),
              );
            }(),
          ],
        );
        debugPrint('_tracks: ${_tracks.length}');
        debugPrint('_albums: ${_albums.length}');
        debugPrint('_artists: ${_artists.length}');
        await sort(notifyListeners: false);
        await _arrangeArtists(notifyListeners: false);
        await playlistsGetFromCache(notifyListeners: false);
        notifyListeners();
        // Check for newly added & deleted [Track]s & update the [Collection] accordingly.
        if (update) {
          // Remove deleted tracks.
          final tracks = [..._tracks];
          final files = [..._tracks.map((e) => e.uri.toFilePath())];
          for (int i = 0; i < files.length; i++) {
            if (!await File(files[i]).exists_()) {
              await delete(
                tracks[i],
                delete: false,
                notifyListeners: false,
              );
            }
          }
          // Add newly added tracks.
          final directory = <File>[];
          for (Directory collectionDirectory in collectionDirectories) {
            for (final object in await collectionDirectory.list_(
                extensions: kSupportedFileTypes)) {
              directory.add(object);
            }
          }
          for (int index = 0; index < directory.length; index++) {
            File file = directory[index];
            if (files.contains(file.path)) {
              continue;
            }
            // Add new tracks.
            try {
              final metadata = <String, dynamic>{
                'uri': file.uri.toString(),
              };
              if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
                try {
                  metadata.addAll(await tagger.parse(
                    libmpv.Media(file.uri.toString()),
                    coverDirectory: albumArtDirectory,
                    timeout: Duration(seconds: 2),
                  ));
                } catch (exception, stacktrace) {
                  debugPrint(exception.toString());
                  debugPrint(stacktrace.toString());
                }
                final track = Track.fromTagger(metadata);
                await _arrange(track);
              } else {
                final _metadata = await MetadataRetriever.fromUri(
                  file.uri,
                  coverDirectory: albumArtDirectory,
                );
                metadata.addAll(_metadata.toJson().cast());
                final track = Track.fromJson(metadata);
                await _arrange(track);
              }
            } catch (exception, stacktrace) {
              debugPrint(exception.toString());
              debugPrint(stacktrace.toString());
            }
            try {
              onProgress?.call(index + 1, directory.length, false);
            } catch (exception) {}
          }
        }
        // Save to cache.
        await sort();
        await saveToCache();
      } catch (exception, stacktrace) {
        // Handle corrupt cache.
        debugPrint(exception.toString());
        debugPrint(stacktrace.toString());
        index(onProgress: onProgress);
      }
    }
    // Cause UI redraw.
    try {
      onProgress?.call(1 << 32, 1 << 32, true);
    } catch (exception) {}
  }

  /// Sorts the music collection contents based upon passed [type].
  ///
  Future<void> sort({CollectionSort? type, bool notifyListeners: true}) async {
    if (type == null) {
      type = collectionSortType;
    } else {
      collectionSortType = type;
    }
    tracks = _tracks.toList();
    tracks.sort((first, second) => (first.timeAdded.millisecondsSinceEpoch)
        .compareTo(second.timeAdded.millisecondsSinceEpoch));
    albums = _albums.toList();
    albums.sort((first, second) => first.timeAdded.compareTo(second.timeAdded));
    if (type == CollectionSort.aToZ ||
        type ==
            CollectionSort
                .artist /* Handled externally & applicable only for albums & other tabs fallback to `CollectionSort.aToZ */) {
      tracks = _tracks.toList();
      tracks.sort((first, second) => first.trackName
          .toLowerCase()
          .compareTo(second.trackName.toLowerCase()));
      albums = _albums.toList();
      albums.sort((first, second) => first.albumName
          .toLowerCase()
          .compareTo(second.albumName.toLowerCase()));
    }
    if (type == CollectionSort.year) {
      tracks = _tracks.toList();
      tracks.sort((first, second) => (int.tryParse(first.year) ?? -1)
          .compareTo(int.tryParse(second.year) ?? -1));
      albums = _albums.toList();
      albums.sort((first, second) => (int.tryParse(first.year) ?? -1)
          .compareTo(int.tryParse(second.year) ?? -1));
    }
    // Only `CollectionSort.aToZ` is available for [artists].
    artists = _artists.toList();
    artists.sort((first, second) => first.artistName
        .toLowerCase()
        .compareTo(second.artistName.toLowerCase()));
    if (collectionOrderType == CollectionOrder.descending) {
      tracks = tracks.reversed.toList();
      albums = albums.reversed.toList();
      artists = artists.reversed.toList();
    }
    if (notifyListeners) {
      this.notifyListeners();
    }
  }

  /// Orders the music collection contents based upon passed [type].
  ///
  Future<void> order({CollectionOrder? type}) async {
    if (type != collectionOrderType && type != null) {
      tracks = tracks.reversed.toList();
      albums = albums.reversed.toList();
      artists = artists.reversed.toList();
      collectionOrderType = type;
    }
    notifyListeners();
  }

  /// Indexes the music collection from scratch clearing the existing cache.
  ///
  /// Deletes the cache file before proceeding.
  ///
  Future<void> index(
      {void Function(int? completed, int total, bool isCompleted)?
          onProgress}) async {
    _albums = HashSet<Album>();
    _tracks = HashSet<Track>();
    _artists = HashSet<Artist>();
    playlists = <Playlist>[];
    final directory = <File>[];
    onProgress?.call(null, directory.length, false);
    for (final collectionDirectory in collectionDirectories)
      directory.addAll(
          await (collectionDirectory.list_(extensions: kSupportedFileTypes)));
    for (int index = 0; index < directory.length; index++) {
      final object = directory[index];
      try {
        final metadata = <String, dynamic>{
          'uri': object.uri.toString(),
        };
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          try {
            metadata.addAll(await tagger.parse(
              libmpv.Media(object.uri.toString()),
              coverDirectory: albumArtDirectory,
              timeout: Duration(seconds: 2),
            ));
          } catch (exception, stacktrace) {
            debugPrint(exception.toString());
            debugPrint(stacktrace.toString());
          }
          final track = Track.fromTagger(metadata);
          await _arrange(
            track,
          );
        } else {
          final _metadata = await MetadataRetriever.fromUri(
            object.uri,
            coverDirectory: albumArtDirectory,
          );
          metadata.addAll(_metadata.toJson().cast());
          final track = Track.fromJson(metadata);
          await _arrange(
            track,
          );
        }
      } catch (exception, stacktrace) {
        debugPrint(exception.toString());
        debugPrint(stacktrace.toString());
      }
      try {
        onProgress?.call(index + 1, directory.length, false);
      } catch (exception) {}
    }
    try {
      onProgress?.call(directory.length, directory.length, true);
    } catch (exception) {}
    await _arrangeArtists(notifyListeners: false);
    await sort(notifyListeners: false);
    await saveToCache();
    await playlistsGetFromCache(notifyListeners: false);
    notifyListeners();
  }

  /// Creates a new [Playlist] in the collection with a given [name].
  /// Returns it's reference after creation.
  ///
  Future<Playlist> playlistAdd(String name) async {
    final Playlist playlist;
    if (playlists.length == 0) {
      playlist = Playlist(
        name: name,
        id: 0,
      );
    } else {
      playlist = Playlist(
        name: name,
        id: playlists.last.id + 1,
      );
    }
    playlists.add(playlist);
    await playlistsSaveToCache();
    notifyListeners();
    return playlist;
  }

  /// Creates a new [Playlist] in the collection.
  ///
  Future<Playlist> playlistCreate(Playlist playlist) async {
    playlists.add(playlist);
    await playlistsSaveToCache();
    notifyListeners();
    return playlist;
  }

  /// Removes a playlist from the collection.
  ///
  Future<void> playlistRemove(Playlist playlist) async {
    for (int index = 0; index < playlists.length; index++) {
      if (playlists[index].id == playlist.id) {
        playlists.removeAt(index);
        break;
      }
    }
    await playlistsSaveToCache();
    notifyListeners();
  }

  /// Adds a [Track] to a [Playlist].
  ///
  Future<void> playlistAddTrack(Playlist playlist, Track track) async {
    for (int index = 0; index < playlists.length; index++) {
      if (playlists[index].id == playlist.id) {
        if (playlist.id == kHistoryPlaylist) {
          final tracks = [track] + [...playlists[index].tracks];
          playlists[index].tracks.clear();
          playlists[index].tracks.addAll(tracks.take(100));
        } else {
          playlists[index].tracks.insert(0, track);
        }
        break;
      }
    }
    await playlistsSaveToCache();
    notifyListeners();
  }

  /// Adds a [List] of [Track]s passed as [tracks], to the [playlist].
  ///
  Future<void> playlistAddTracks(Playlist playlist, List<Track> tracks) async {
    for (int index = 0; index < playlists.length; index++) {
      if (playlists[index].id == playlist.id) {
        if (playlist.id == kHistoryPlaylist) {
          final res = [...tracks, ...playlists[index].tracks];
          playlists[index].tracks.clear();
          playlists[index].tracks.addAll(res.take(100));
        } else {
          playlists[index].tracks.insertAll(0, tracks);
        }
        break;
      }
    }
    await playlistsSaveToCache();
    notifyListeners();
  }

  /// Removes a track from a playlist.
  ///
  Future<void> playlistRemoveTrack(Playlist playlist, Track track) async {
    for (int i = 0; i < playlists.length; i++) {
      if (playlists[i].id == playlist.id) {
        for (int j = 0; j < playlist.tracks.length; j++) {
          if (playlists[i].tracks[j] == track) {
            playlists[i].tracks.removeAt(j);
            break;
          }
        }
        break;
      }
    }
    await playlistsSaveToCache();
    notifyListeners();
  }

  /// Save playlists to the cache.
  ///
  Future<void> playlistsSaveToCache() async {
    _playlistStorage.write(
      {
        'playlists': playlists.map((e) => e.toJson()).toList(),
      },
    );
  }

  /// Gets all the playlists present in the cache.
  ///
  Future<void> playlistsGetFromCache({bool notifyListeners: true}) async {
    final data = await _playlistStorage.read();
    playlists = data['playlists']!
        .map((e) => Playlist.fromJson(e))
        .toList()
        .cast<Playlist>();
    if (notifyListeners) {
      this.notifyListeners();
    }
  }

  /// Adds a given [track] to the collection & updates the cache.
  Future<void> arrange(Track track) async {
    await _arrange(track);
    await _arrangeArtists(notifyListeners: false);
    await saveToCache();
    await refresh();
  }

  /// Indexes a track into album & artist models.
  ///
  Future<void> _arrange(Track track) async {
    if (!_albums.contains(
      Album(
        albumName: track.albumName,
        albumArtistName: track.albumArtistName,
        year: track.year,
      ),
    )) {
      // Run as asynchronous suspension.
      _albums.add(
        Album(
          albumName: track.albumName,
          year: track.year,
          albumArtistName: track.albumArtistName,
        )..tracks.add(track),
      );
    } else {
      _albums
          .lookup(Album(
            albumName: track.albumName,
            albumArtistName: track.albumArtistName,
            year: track.year,
          ))
          ?.tracks
          .add(track);
    }
    // A new album artist gets discovered.
    if (!albumArtists.containsKey(AlbumArtist(track.albumArtistName))) {
      // Create new [List] and append the new [Album] to its name.
      albumArtists[AlbumArtist(track.albumArtistName)] = HashSet<Album>();
    }
    for (String artistName in track.trackArtistNames) {
      if (!_artists.contains(Artist(artistName: artistName))) {
        _artists.add(
          Artist(
            artistName: artistName,
          )..tracks.add(track),
        );
      } else {
        _artists.lookup(Artist(artistName: artistName))?.tracks.add(track);
      }
    }
    _tracks.add(track);
  }

  /// Populates all the [albumArtists] & discovered artists' albums after running the [_arrange] loop.
  ///
  Future<void> _arrangeArtists({bool notifyListeners: true}) async {
    for (final album in _albums) {
      final all = <String>[];
      album.tracks.forEach((Track track) {
        track.trackArtistNames.forEach((artistName) {
          if (!all.contains(artistName)) all.add(artistName);
        });
      });
      for (final artistName in all) {
        if (!_artists
            .lookup(Artist(artistName: artistName))!
            .albums
            .contains(album))
          _artists.lookup(Artist(artistName: artistName))!.albums.add(album);
      }
      if (!albumArtists[AlbumArtist(album.albumArtistName)]!.contains(album)) {
        albumArtists[AlbumArtist(album.albumArtistName)]!.add(album);
      }
    }
    if (notifyListeners) {
      this.notifyListeners();
    }
  }

  /// Redraws the collection.
  ///
  Future<void> redraw() async {
    await sort(notifyListeners: false);
    // Explicitly populate so that [Artist] sort in [Album] tab doesn't present empty screen at the time of indexing.
    for (Album album in _albums) {
      if (!albumArtists[AlbumArtist(album.albumArtistName)]!.contains(album)) {
        albumArtists[AlbumArtist(album.albumArtistName)]!.add(album);
      }
    }
  }

  @override
  // ignore: must_call_super
  void dispose() {}

  HashSet<Album> _albums = HashSet<Album>();
  HashSet<Track> _tracks = HashSet<Track>();
  HashSet<Artist> _artists = HashSet<Artist>();

  SafeSessionStorage get _albumStorage => SafeSessionStorage(
        path.join(cacheDirectory.path, kCollectionAlbumCacheFileName),
        fallback: {'albums': []},
      );
  SafeSessionStorage get _trackStorage => SafeSessionStorage(
        path.join(cacheDirectory.path, kCollectionTrackCacheFileName),
        fallback: {'tracks': []},
      );
  SafeSessionStorage get _artistStorage => SafeSessionStorage(
        path.join(cacheDirectory.path, kCollectionArtistCacheFileName),
        fallback: {'artists': []},
      );
  SafeSessionStorage get _playlistStorage => SafeSessionStorage(
        path.join(cacheDirectory.path, kPlaylistsCacheFileName),
        fallback: {
          'playlists': [
            {
              'name': 'History',
              'id': kHistoryPlaylist,
              'tracks': [],
            },
            {
              'name': 'Liked Songs',
              'id': kLikedSongsPlaylist,
              'tracks': [],
            },
          ],
        },
      );

  /// `libmpv.dart` [Tagger] instance.
  final Tagger tagger = Tagger();

  static HashSet<Track> parseTrackHashSetFromData(dynamic data) =>
      HashSet<Track>.from(
        data['tracks'].map((e) => Track.fromJson(e)).cast<Track>(),
      );

  static List<dynamic> parseAlbumHashSetFromData(dynamic data) {
    final splayTreeMap = SplayTreeMap<AlbumArtist, HashSet<Album>>();
    final hashSet = HashSet<Album>.from(data['albums'].map((e) {
      final album = Album.fromJson(e);
      if (!splayTreeMap.containsKey(AlbumArtist(album.albumArtistName))) {
        splayTreeMap[AlbumArtist(album.albumArtistName)] = HashSet<Album>();
      }
      return album;
    }).cast<Album>());
    return [
      hashSet,
      splayTreeMap,
    ];
  }

  static HashSet<Artist> parseArtistHashSetFromData(dynamic data) =>
      HashSet<Artist>.from(
        data['artists'].map((e) => Artist.fromJson(e)).cast<Artist>(),
      );
}

/// Types of sorts available.
///
enum CollectionSort {
  aToZ,
  dateAdded,
  year,

  /// A new sort which arranges the [AlbumScreen] & [ArtistScreen] with a sidebar that allows to view [Artist]s [Track]s from a specified artist.
  /// Currently exclusive to desktop.
  artist,
}

/// Types of orders available.
///
enum CollectionOrder { ascending, descending }

/// Supported file extensions.
/// Used for identifying the audio files during indexing the collection.
///
const List<String> kSupportedFileTypes = [
  'OGG',
  'OGA',
  'OGX',
  'AAC',
  'M4A',
  'MP3',
  'WMA',
  'WAV',
  'FLAC',
  'OPUS',
  'AIFF',
];

/// Album art files.
/// List of file names that are checked in [Track]'s [Directory] to use as fallback album art if one cannot be retrieved from the metadata.
///
const List<String> kAlbumArtFileNames = [
  'cover.jpg',
  'Folder.jpg',
];

/// Unknown album art from assets to write to the disk.
const String kUnknownAlbumArtRootBundle = 'assets/images/default_album_art.png';

/// Name of the sub directory inside [Collection.cacheDirectory] where retrieved album arts are saved.
const String kAlbumArtsDirectoryName = 'AlbumArts';

/// Cache file to store collection.
@Deprecated(
  'Now [kCollectionTrackCacheFileName], [kCollectionAlbumCacheFileName] & [kCollectionArtistCacheFileName] is used.',
)
const String kCollectionCacheFileName = 'Collection.JSON';

const String kCollectionTrackCacheFileName = 'Tracks.JSON';
const String kCollectionAlbumCacheFileName = 'Albums.JSON';
const String kCollectionArtistCacheFileName = 'Artists.JSON';

/// Cache file to store playlists.
const String kPlaylistsCacheFileName = 'Playlists.JSON';

/// Name of the file to use as fallback when no album art is discovered.
const String kUnknownAlbumArtFileName = 'UnknownAlbum.PNG';

const int kHistoryPlaylist = -2;
const int kLikedSongsPlaylist = -1;

extension CollectionTrackExtension on Track {
  String get albumArtFileName =>
      '$trackName$albumName$albumArtistName'
          .replaceAll(RegExp(kArtworkFileNameRegex), '') +
      '.PNG';

  /// To support older generated cache. Only used in [getAlbumArt] now as a fallback check.
  String get legacyAlbumArtFileName =>
      '$albumName$albumArtistName'
          .replaceAll(RegExp(kArtworkFileNameRegex), '') +
      '.PNG';
}

/// Prettified JSON serialization.
const encoder = convert.JsonEncoder.withIndent('  ');
