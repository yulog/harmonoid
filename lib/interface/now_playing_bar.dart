/// This file is a part of Harmonoid (https://github.com/harmonoid/harmonoid).
///
/// Copyright © 2020-2022, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
///
/// Use of this source code is governed by the End-User License Agreement for Harmonoid that can be found in the EULA.txt file.
///

import 'dart:core';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:libmpv/libmpv.dart';
import 'package:animations/animations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:extended_image/extended_image.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:harmonoid/core/collection.dart';
import 'package:harmonoid/core/hotkeys.dart';
import 'package:harmonoid/core/playback.dart';
import 'package:harmonoid/core/configuration.dart';
import 'package:harmonoid/interface/home.dart';
import 'package:harmonoid/interface/collection/artist.dart';
import 'package:harmonoid/utils/widgets.dart';
import 'package:harmonoid/utils/rendering.dart';
import 'package:harmonoid/utils/dimensions.dart';
import 'package:harmonoid/state/desktop_now_playing_controller.dart';
import 'package:harmonoid/state/now_playing_color_palette.dart';
import 'package:harmonoid/models/media.dart';
import 'package:harmonoid/constants/language.dart';

class NowPlayingBar extends StatefulWidget {
  const NowPlayingBar({Key? key}) : super(key: key);

  NowPlayingBarState createState() => NowPlayingBarState();
}

class NowPlayingBarState extends State<NowPlayingBar>
    with TickerProviderStateMixin {
  late AnimationController playOrPause;
  late VoidCallback listener;
  List<Widget> fills = [];
  Track? track;
  bool isShuffling = Playback.instance.isShuffling;
  bool showAlbumArtButton = false;
  bool controlPanelVisible = false;

  @override
  void initState() {
    super.initState();
    playOrPause = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 200),
    );
    listener = () async {
      if (Playback.instance.isPlaying) {
        playOrPause.forward();
      } else {
        playOrPause.reverse();
      }
      if (!Configuration.instance.dynamicNowPlayingBarColoring ||
          Playback.instance.index < 0 ||
          Playback.instance.index >= Playback.instance.tracks.length) {
        return;
      }
      final track = Playback.instance.tracks[Playback.instance.index];
      if (this.track != track) {
        this.track = track;
        isShuffling = Playback.instance.isShuffling;
      }
    };
    Playback.instance.addListener(listener);
    NowPlayingColorPalette.instance.addListener(colorPaletteListener);
  }

  void colorPaletteListener() {
    fills.add(
      TweenAnimationBuilder(
        tween: Tween<double>(begin: 0.0, end: 40.0),
        duration: Duration(
          milliseconds: (1000 * (400 / MediaQuery.of(context).size.width) ~/ 1),
        ),
        onEnd: () {
          if (fills.length > 2) {
            fills.removeAt(0);
          }
        },
        curve: Curves.elasticInOut,
        child: Container(
          height: kDesktopNowPlayingBarHeight,
          width: MediaQuery.of(context).size.width,
          alignment: Alignment.center,
          child: ClipRect(
            child: Container(
              height: kDesktopNowPlayingBarHeight,
              width: kDesktopNowPlayingBarHeight,
              decoration: BoxDecoration(
                color: NowPlayingColorPalette.instance.palette == null
                    ? Theme.of(context).cardColor
                    : NowPlayingColorPalette.instance.palette!.first
                        .withOpacity(1.0),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        builder: (context, value, child) => Transform.scale(
          scale: value as double,
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    Playback.instance.removeListener(listener);
    NowPlayingColorPalette.instance.removeListener(colorPaletteListener);
    super.dispose();
  }

  double getPlaybackDuration(Playback playback) =>
      playback.duration.inMilliseconds.toDouble();

  double getPlaybackPosition(Playback playback) {
    var duration = getPlaybackDuration(playback);
    var position = playback.position.inMilliseconds.toDouble();
    if (position > duration) return duration;
    if (duration < 0 || position < 0) return 0;
    return position;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NowPlayingColorPalette>(
      builder: (context, colors, _) => isDesktop
          ? Consumer<Playback>(
              builder: (context, playback, _) => ClipRect(
                clipBehavior: Clip.antiAlias,
                child: Container(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Material(
                    clipBehavior: Clip.antiAlias,
                    color: Colors.transparent,
                    elevation: 12.0,
                    child: Stack(
                      children: [
                        ...fills,
                        if (fills.isEmpty)
                          Container(
                            height: kDesktopNowPlayingBarHeight,
                            width: MediaQuery.of(context).size.width,
                            alignment: Alignment.center,
                            color: Theme.of(context).cardColor,
                          ),
                        Material(
                          clipBehavior: Clip.antiAlias,
                          color: Colors.transparent,
                          child: Container(
                            height: 84.0,
                            child: Row(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: () {
                                    if (playback.isBuffering) {
                                      return Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 24.0,
                                          ),
                                          Container(
                                            height: 24.0,
                                            width: 24.0,
                                            child: CircularProgressIndicator(
                                              valueColor:
                                                  AlwaysStoppedAnimation(
                                                Theme.of(context).primaryColor,
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 24.0,
                                          ),
                                          Expanded(
                                            child: Text(
                                              Language.instance.BUFFERING,
                                              style:
                                                  Theme.of(context)
                                                      .textTheme
                                                      .headline2
                                                      ?.copyWith(
                                                        color:
                                                            (colors.palette ??
                                                                        [
                                                                          Theme.of(context)
                                                                              .cardColor
                                                                        ])
                                                                    .first
                                                                    .isDark
                                                                ? Colors.white
                                                                : Colors.black,
                                                      ),
                                            ),
                                          ),
                                        ],
                                      );
                                    } else if (playback.tracks.isEmpty ||
                                        playback.tracks.length <=
                                                playback.index &&
                                            0 > playback.index) {
                                      return Container();
                                    } else {
                                      return Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          MouseRegion(
                                            onEnter: (e) {
                                              setState(() {
                                                showAlbumArtButton = true;
                                              });
                                            },
                                            onExit: (e) {
                                              setState(() {
                                                showAlbumArtButton = false;
                                              });
                                            },
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          0.0),
                                                  child: AnimatedSwitcher(
                                                    duration: const Duration(
                                                        milliseconds: 300),
                                                    transitionBuilder:
                                                        (child, animation) =>
                                                            FadeTransition(
                                                      opacity: animation,
                                                      child: child,
                                                    ),
                                                    child: ExtendedImage(
                                                      key: Key(playback.index
                                                          .toString()),
                                                      image: getAlbumArt(
                                                        playback.tracks[playback
                                                            .index
                                                            .clamp(
                                                                0,
                                                                playback.tracks
                                                                        .length -
                                                                    1)],
                                                        small: true,
                                                      ),
                                                      height: 84.0,
                                                      width: 84.0,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                ),
                                                TweenAnimationBuilder(
                                                  tween: Tween<double>(
                                                    begin: 0.0,
                                                    end: showAlbumArtButton
                                                        ? 1.0
                                                        : 0.0,
                                                  ),
                                                  duration: Duration(
                                                      milliseconds: 100),
                                                  curve: Curves.easeInOut,
                                                  child: Material(
                                                    color: Colors.transparent,
                                                    child: InkWell(
                                                      onTap: () {
                                                        DesktopNowPlayingController
                                                            .instance
                                                            .maximize();
                                                      },
                                                      child: Container(
                                                        color: Colors.black38,
                                                        height: 84.0,
                                                        width: 84.0,
                                                        child: Icon(
                                                          Icons.image,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  builder:
                                                      (context, value, child) =>
                                                          Opacity(
                                                    opacity: value as double,
                                                    child: child,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(
                                            width: 10.0,
                                          ),
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  playback
                                                      .tracks[playback.index
                                                          .clamp(
                                                              0,
                                                              playback.tracks
                                                                      .length -
                                                                  1)]
                                                      .trackName
                                                      .overflow,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .headline1
                                                      ?.copyWith(
                                                        color:
                                                            (colors.palette ??
                                                                        [
                                                                          Theme.of(context)
                                                                              .cardColor
                                                                        ])
                                                                    .first
                                                                    .isDark
                                                                ? Colors.white
                                                                : Colors.black,
                                                      ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                HyperLink(
                                                  text: TextSpan(
                                                    children: playback
                                                        .tracks[playback.index
                                                            .clamp(
                                                                0,
                                                                playback.tracks
                                                                        .length -
                                                                    1)]
                                                        .trackArtistNames
                                                        .take(2)
                                                        .map(
                                                          (e) => TextSpan(
                                                            text: e,
                                                            recognizer: !Plugins.isWebMedia(playback
                                                                    .tracks[playback
                                                                        .index
                                                                        .clamp(
                                                                            0,
                                                                            playback.tracks.length -
                                                                                1)]
                                                                    .uri)
                                                                ? (TapGestureRecognizer()
                                                                  ..onTap = () {
                                                                    navigatorKey
                                                                        .currentState
                                                                        ?.push(
                                                                      PageRouteBuilder(
                                                                        pageBuilder: ((context,
                                                                                animation,
                                                                                secondaryAnimation) =>
                                                                            FadeThroughTransition(
                                                                              animation: animation,
                                                                              secondaryAnimation: secondaryAnimation,
                                                                              child: ArtistScreen(
                                                                                artist: Collection.instance.artistsSet.lookup(Artist(artistName: e))!,
                                                                              ),
                                                                            )),
                                                                      ),
                                                                    );
                                                                  })
                                                                : null,
                                                          ),
                                                        )
                                                        .toList()
                                                      ..insert(
                                                        1,
                                                        TextSpan(
                                                            text: playback
                                                                        .tracks[playback
                                                                            .index
                                                                            .clamp(0,
                                                                                playback.tracks.length - 1)]
                                                                        .trackArtistNames
                                                                        .take(2)
                                                                        .length ==
                                                                    2
                                                                ? ', '
                                                                : ''),
                                                      ),
                                                  ),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .headline3
                                                      ?.copyWith(
                                                        color:
                                                            (colors.palette ??
                                                                        [
                                                                          Theme.of(context)
                                                                              .cardColor
                                                                        ])
                                                                    .first
                                                                    .isDark
                                                                ? Colors.white
                                                                : Colors.black,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(
                                            width: 10.0,
                                          ),
                                        ],
                                      );
                                    }
                                  }(),
                                ),
                                Stack(
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    Container(
                                      margin: EdgeInsets.only(
                                        top: 54.0,
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            margin:
                                                EdgeInsets.only(bottom: 2.0),
                                            child: Text(
                                              playback.position.label,
                                              style: TextStyle(
                                                color: (colors.palette ??
                                                            [
                                                              Theme.of(context)
                                                                  .cardColor
                                                            ])
                                                        .first
                                                        .isDark
                                                    ? Colors.white
                                                    : Colors.black,
                                                fontSize: 14.0,
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 12.0,
                                          ),
                                          getPlaybackPosition(playback) <=
                                                  getPlaybackDuration(playback)
                                              ? Container(
                                                  width: 360.0,
                                                  child: ScrollableSlider(
                                                    min: 0.0,
                                                    max: getPlaybackDuration(
                                                        playback),
                                                    value: getPlaybackPosition(
                                                        playback),
                                                    color: colors.palette?.last,
                                                    secondaryColor:
                                                        colors.palette?.first,
                                                    onChanged: (value) {
                                                      playback.seek(
                                                        Duration(
                                                          milliseconds:
                                                              value.toInt(),
                                                        ),
                                                      );
                                                    },
                                                    onScrolledUp: () {
                                                      if (Playback.instance
                                                              .position >=
                                                          Playback.instance
                                                              .duration) return;
                                                      playback.seek(
                                                        playback.position +
                                                            Duration(
                                                                seconds: 10),
                                                      );
                                                    },
                                                    onScrolledDown: () {
                                                      if (Playback.instance
                                                              .position <=
                                                          Duration.zero) return;
                                                      playback.seek(
                                                        playback.position -
                                                            Duration(
                                                                seconds: 10),
                                                      );
                                                    },
                                                  ),
                                                )
                                              : Container(),
                                          SizedBox(
                                            width: 12.0,
                                          ),
                                          Container(
                                            margin:
                                                EdgeInsets.only(bottom: 2.0),
                                            child: Text(
                                              playback.duration.label,
                                              style: TextStyle(
                                                color: (colors.palette ??
                                                            [
                                                              Theme.of(context)
                                                                  .cardColor
                                                            ])
                                                        .first
                                                        .isDark
                                                    ? Colors.white
                                                    : Colors.black,
                                                fontSize: 14.0,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      margin: EdgeInsets.only(
                                          top: 8.0, bottom: 26.0),
                                      child: Row(
                                        children: [
                                          // Transform.rotate(
                                          //   angle: pi,
                                          //   child: Container(
                                          //     width: 84.0,
                                          //     child: ScrollableSlider(
                                          //       min: 0.0,
                                          //       max: 2.0,
                                          //       value: playback.rate,
                                          //       color: palette?.last,
                                          //       secondaryColor: palette?.first,
                                          //       onScrolledUp: () {
                                          //         playback.setRate(
                                          //           (playback.rate + 0.05)
                                          //               .clamp(0.0, 2.0),
                                          //         );
                                          //       },
                                          //       onScrolledDown: () {
                                          //         playback.setRate(
                                          //           (playback.rate - 0.05)
                                          //               .clamp(0.0, 2.0),
                                          //         );
                                          //       },
                                          //       onChanged: (value) {
                                          //         playback.setRate(value);
                                          //       },
                                          //     ),
                                          //   ),
                                          // ),
                                          // SizedBox(
                                          //   width: 12.0,
                                          // ),
                                          // IconButton(
                                          //   onPressed: () {
                                          //     playback.setRate(1.0);
                                          //   },
                                          //   iconSize: 20.0,
                                          //   color: (palette ??
                                          //               [
                                          //                 Theme.of(context)
                                          //                     .cardColor
                                          //               ])
                                          //           .first
                                          //           .isDark
                                          //       ? Colors.white.withOpacity(0.87)
                                          //       : Colors.black87,
                                          //   splashRadius: 18.0,
                                          //   tooltip:
                                          //       Language.instance.RESET_SPEED,
                                          //   icon: Icon(
                                          //     Icons.speed,
                                          //   ),
                                          // ),
                                          if (playback.tracks.isNotEmpty &&
                                              Plugins.isWebMedia(playback
                                                  .tracks[playback.index.clamp(
                                                      0,
                                                      playback.tracks.length -
                                                          1)]
                                                  .uri))
                                            IconButton(
                                              splashRadius: 20.0,
                                              iconSize: 20.0,
                                              onPressed: () {
                                                Clipboard.setData(ClipboardData(
                                                    text: playback
                                                        .tracks[playback.index]
                                                        .uri
                                                        .toString()));
                                              },
                                              icon: Icon(
                                                Icons.link,
                                              ),
                                              color: (colors.palette ??
                                                          [
                                                            Theme.of(context)
                                                                .cardColor
                                                          ])
                                                      .first
                                                      .isDark
                                                  ? Colors.white
                                                      .withOpacity(0.87)
                                                  : Colors.black87,
                                              tooltip:
                                                  Language.instance.COPY_LINK,
                                            ),
                                          Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              Container(
                                                height: 32.0,
                                                width: 32.0,
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          20.0),
                                                  border: playback.isShuffling
                                                      ? Border.all(
                                                          width: 1.6,
                                                          color: (colors.palette ??
                                                                      [
                                                                        Theme.of(context)
                                                                            .cardColor
                                                                      ])
                                                                  .first
                                                                  .isDark
                                                              ? Colors.white
                                                                  .withOpacity(
                                                                      0.87)
                                                              : Colors.black87,
                                                        )
                                                      : null,
                                                ),
                                              ),
                                              IconButton(
                                                onPressed:
                                                    playback.toggleShuffle,
                                                iconSize: 20.0,
                                                color: (colors.palette ??
                                                            [
                                                              Theme.of(context)
                                                                  .cardColor
                                                            ])
                                                        .first
                                                        .isDark
                                                    ? Colors.white
                                                        .withOpacity(0.87)
                                                    : Colors.black87,
                                                splashRadius: 18.0,
                                                tooltip:
                                                    Language.instance.SHUFFLE,
                                                icon: Icon(
                                                  Icons.shuffle,
                                                ),
                                              ),
                                            ],
                                          ),
                                          IconButton(
                                            onPressed: playback.isFirstTrack
                                                ? null
                                                : playback.previous,
                                            disabledColor: (colors.palette ??
                                                        [
                                                          Theme.of(context)
                                                              .cardColor
                                                        ])
                                                    .first
                                                    .isDark
                                                ? Colors.white.withOpacity(0.45)
                                                : Colors.black45,
                                            iconSize: 24.0,
                                            color: (colors.palette ??
                                                        [
                                                          Theme.of(context)
                                                              .cardColor
                                                        ])
                                                    .first
                                                    .isDark
                                                ? Colors.white.withOpacity(0.87)
                                                : Colors.black87,
                                            splashRadius: 18.0,
                                            tooltip: Language.instance.PREVIOUS,
                                            mouseCursor:
                                                SystemMouseCursors.click,
                                            icon: Icon(
                                              Icons.skip_previous,
                                            ),
                                          ),
                                          FloatingActionButton(
                                            foregroundColor: (colors.palette ??
                                                        [
                                                          Theme.of(context)
                                                              .primaryColor
                                                        ])
                                                    .last
                                                    .isDark
                                                ? Colors.white
                                                : Color(0xFF212121),
                                            backgroundColor: (colors.palette ??
                                                    [
                                                      Theme.of(context)
                                                          .primaryColor
                                                    ])
                                                .last,
                                            onPressed: playback.playOrPause,
                                            elevation: 2.0,
                                            tooltip: playback.isPlaying
                                                ? Language.instance.PAUSE
                                                : Language.instance.PLAY,
                                            child: AnimatedIcon(
                                              icon: AnimatedIcons.play_pause,
                                              size: 32.0,
                                              progress: playOrPause,
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: playback.isLastTrack
                                                ? null
                                                : playback.next,
                                            iconSize: 24.0,
                                            disabledColor: (colors.palette ??
                                                        [
                                                          Theme.of(context)
                                                              .cardColor
                                                        ])
                                                    .first
                                                    .isDark
                                                ? Colors.white.withOpacity(0.45)
                                                : Colors.black45,
                                            color: (colors.palette ??
                                                        [
                                                          Theme.of(context)
                                                              .cardColor
                                                        ])
                                                    .first
                                                    .isDark
                                                ? Colors.white.withOpacity(0.87)
                                                : Colors.black87,
                                            splashRadius: 18.0,
                                            tooltip: Language.instance.NEXT,
                                            mouseCursor:
                                                SystemMouseCursors.click,
                                            icon: Icon(
                                              Icons.skip_next,
                                            ),
                                          ),
                                          Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              Container(
                                                height: 32.0,
                                                width: 32.0,
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          20.0),
                                                  border: playback
                                                              .playlistLoopMode !=
                                                          PlaylistLoopMode.none
                                                      ? Border.all(
                                                          width: 1.6,
                                                          color: (colors.palette ??
                                                                      [
                                                                        Theme.of(context)
                                                                            .cardColor
                                                                      ])
                                                                  .first
                                                                  .isDark
                                                              ? Colors.white
                                                                  .withOpacity(
                                                                      0.87)
                                                              : Colors.black87,
                                                        )
                                                      : null,
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: () {
                                                  if (playback
                                                          .playlistLoopMode ==
                                                      PlaylistLoopMode.loop) {
                                                    playback
                                                        .setPlaylistLoopMode(
                                                      PlaylistLoopMode.none,
                                                    );
                                                    return;
                                                  }
                                                  playback.setPlaylistLoopMode(
                                                    PlaylistLoopMode
                                                        .values[playback
                                                            .playlistLoopMode
                                                            .index +
                                                        1],
                                                  );
                                                },
                                                tooltip:
                                                    Language.instance.REPEAT,
                                                iconSize: 20.0,
                                                color: (colors.palette ??
                                                            [
                                                              Theme.of(context)
                                                                  .cardColor
                                                            ])
                                                        .first
                                                        .isDark
                                                    ? Colors.white
                                                        .withOpacity(0.87)
                                                    : Colors.black87,
                                                splashRadius: 18.0,
                                                icon: Icon(
                                                  playback.playlistLoopMode ==
                                                          PlaylistLoopMode
                                                              .single
                                                      ? Icons.repeat_one
                                                      : Icons.repeat,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (playback.tracks.isNotEmpty &&
                                              Plugins.isWebMedia(playback
                                                  .tracks[playback.index.clamp(
                                                      0,
                                                      playback.tracks.length -
                                                          1)]
                                                  .uri))
                                            IconButton(
                                              splashRadius: 20.0,
                                              iconSize: 18.0,
                                              onPressed: () {
                                                launchUrl(
                                                  playback
                                                      .tracks[playback.index
                                                          .clamp(
                                                              0,
                                                              playback.tracks
                                                                      .length -
                                                                  1)]
                                                      .uri,
                                                  mode: LaunchMode
                                                      .externalApplication,
                                                );
                                              },
                                              icon: Icon(
                                                Icons.open_in_new,
                                              ),
                                              color: (colors.palette ??
                                                          [
                                                            Theme.of(context)
                                                                .cardColor
                                                          ])
                                                      .first
                                                      .isDark
                                                  ? Colors.white
                                                      .withOpacity(0.87)
                                                  : Colors.black87,
                                              tooltip: Language
                                                  .instance.OPEN_IN_BROWSER,
                                            ),
                                          // IconButton(
                                          //   onPressed: () =>
                                          //       playback.setPitch(1.0),
                                          //   iconSize: 20.0,
                                          //   color: (palette ??
                                          //               [
                                          //                 Theme.of(context)
                                          //                     .cardColor
                                          //               ])
                                          //           .first
                                          //           .isDark
                                          //       ? Colors.white.withOpacity(0.87)
                                          //       : Colors.black87,
                                          //   splashRadius: 18.0,
                                          //   tooltip:
                                          //       Language.instance.RESET_PITCH,
                                          //   icon:
                                          //       Icon(FluentIcons.pulse_20_filled),
                                          // ),
                                          // SizedBox(
                                          //   width: 12.0,
                                          // ),
                                          // Container(
                                          //   width: 84.0,
                                          //   child: ScrollableSlider(
                                          //     min: 0.5,
                                          //     max: 1.5,
                                          //     value: playback.pitch,
                                          //     color: palette?.last,
                                          //     secondaryColor: palette?.first,
                                          //     onScrolledUp: () {
                                          //       playback.setPitch(
                                          //         (playback.pitch + 0.05)
                                          //             .clamp(0.5, 1.5),
                                          //       );
                                          //     },
                                          //     onScrolledDown: () {
                                          //       playback.setPitch(
                                          //         (playback.pitch - 0.05)
                                          //             .clamp(0.5, 1.5),
                                          //       );
                                          //     },
                                          //     onChanged: (value) {
                                          //       playback.setPitch(value);
                                          //     },
                                          //   ),
                                          // ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                Expanded(
                                  child: Consumer<DesktopNowPlayingController>(
                                    builder: (context,
                                            desktopNowPlayingController, _) =>
                                        Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          onPressed: playback.toggleMute,
                                          iconSize: 20.0,
                                          color: (colors.palette ??
                                                      [
                                                        Theme.of(context)
                                                            .cardColor
                                                      ])
                                                  .first
                                                  .isDark
                                              ? Colors.white.withOpacity(0.87)
                                              : Colors.black87,
                                          splashRadius: 18.0,
                                          tooltip: playback.isMuted
                                              ? Language.instance.UNMUTE
                                              : Language.instance.MUTE,
                                          icon: Icon(
                                            playback.volume == 0.0
                                                ? Icons.volume_off
                                                : Icons.volume_up,
                                          ),
                                        ),
                                        SizedBox(
                                          width: 4.0,
                                        ),
                                        Container(
                                          width: 84.0,
                                          child: ScrollableSlider(
                                            min: 0,
                                            max: 100.0,
                                            value: playback.volume,
                                            color: colors.palette?.last,
                                            secondaryColor:
                                                colors.palette?.first,
                                            onScrolledUp: () {
                                              playback.setVolume(
                                                (playback.volume + 5.0)
                                                    .clamp(0.0, 100.0),
                                              );
                                            },
                                            onScrolledDown: () {
                                              playback.setVolume(
                                                (playback.volume - 5.0)
                                                    .clamp(0.0, 100.0),
                                              );
                                            },
                                            onChanged: (value) {
                                              playback.setVolume(value);
                                            },
                                          ),
                                        ),
                                        SizedBox(
                                          width: 16.0,
                                        ),
                                        IconButton(
                                          onPressed: () {
                                            {
                                              if (!controlPanelVisible) {
                                                controlPanelVisible = true;
                                                navigatorKey.currentState?.push(
                                                  RawDialogRoute(
                                                    transitionDuration:
                                                        Duration.zero,
                                                    barrierDismissible: true,
                                                    barrierLabel:
                                                        MaterialLocalizations
                                                                .of(context)
                                                            .modalBarrierDismissLabel,
                                                    barrierColor:
                                                        Colors.transparent,
                                                    pageBuilder:
                                                        (context, __, ___) =>
                                                            ControlPanel(
                                                      onPop: () =>
                                                          controlPanelVisible =
                                                              false,
                                                    ),
                                                  ),
                                                );
                                              } else {
                                                controlPanelVisible = false;
                                                navigatorKey.currentState
                                                    ?.maybePop();
                                              }
                                            }
                                          },
                                          iconSize: 20.0,
                                          color: (colors.palette ??
                                                      [
                                                        Theme.of(context)
                                                            .cardColor
                                                      ])
                                                  .first
                                                  .isDark
                                              ? Colors.white.withOpacity(0.87)
                                              : Colors.black87,
                                          splashRadius: 18.0,
                                          tooltip:
                                              Language.instance.CONTROL_PANEL,
                                          icon: Icon(Icons.more_horiz),
                                        ),
                                        SizedBox(
                                          width: 16.0,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : Container(),
    );
  }
}

class ControlPanel extends StatefulWidget {
  final double? x;

  final void Function() onPop;
  ControlPanel({
    Key? key,
    this.x,
    required this.onPop,
  }) : super(key: key);

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  double end = 0.0;
  bool focused = false;
  List<TextEditingController> controllers = [
    TextEditingController(
      text: Playback.instance.rate.toStringAsFixed(2),
    ),
    TextEditingController(
      text: Playback.instance.pitch.toStringAsFixed(2),
    ),
  ];

  @override
  void initState() {
    super.initState();
    Playback.instance.addListener(listener);
  }

  @override
  void dispose() {
    Playback.instance.removeListener(listener);
    controllers.forEach((controller) => controller.dispose());

    super.dispose();
  }

  void listener() {
    if (!focused) {
      if (Playback.instance.rate.toStringAsFixed(2) != controllers[0].text) {
        controllers[0].text = Playback.instance.rate.toStringAsFixed(2);
      }
      if (Playback.instance.pitch.toStringAsFixed(2) != controllers[1].text) {
        controllers[1].text = Playback.instance.pitch.toStringAsFixed(2);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: WillPopScope(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).maybePop();
                },
                child: Container(
                  color: Colors.transparent,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
            Container(
              alignment: Alignment.bottomRight,
              child: TweenAnimationBuilder(
                tween: Tween<double>(
                  begin: 156.0,
                  end: end,
                ),
                curve: Curves.easeInOut,
                duration: Duration(milliseconds: 160),
                child: Consumer<Playback>(
                  builder: (context, playback, _) => Column(
                    children: [
                      const SizedBox(height: 16.0),
                      Row(
                        children: [
                          const SizedBox(width: 20.0),
                          Text(
                            Language.instance.CONTROL_PANEL,
                            style: Theme.of(context).textTheme.headline1,
                          ),
                          Transform.translate(
                            offset: Offset(2.0, -6.0),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context).dividerColor,
                                  width: 1.0,
                                ),
                              ),
                              padding: EdgeInsets.all(1.0),
                              child: Text(
                                Language.instance.BETA.toUpperCase(),
                                style: Theme.of(context)
                                    .textTheme
                                    .headline5
                                    ?.copyWith(
                                      fontSize: 10.0,
                                    ),
                              ),
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                      const SizedBox(height: 12.0),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(width: 8.0),
                          IconButton(
                            padding: EdgeInsets.all(8.0),
                            onPressed: () {
                              playback.setRate(1.0);
                            },
                            iconSize: 20.0,
                            splashRadius: 18.0,
                            tooltip: Language.instance.RESET_SPEED,
                            icon: Icon(
                              Icons.speed,
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          Expanded(
                            child: ScrollableSlider(
                              min: 0.0,
                              max: 2.0,
                              value: playback.rate.clamp(0.5, 2.0),
                              onScrolledUp: () {
                                playback.setRate(
                                  (playback.rate + 0.05).clamp(0.0, 2.0),
                                );
                              },
                              onScrolledDown: () {
                                playback.setRate(
                                  (playback.rate - 0.05).clamp(0.0, 2.0),
                                );
                              },
                              onChanged: (value) {
                                playback.setRate(value);
                              },
                            ),
                          ),
                          const SizedBox(width: 16.0),
                          Container(
                            width: 42.0,
                            height: 32.0,
                            padding: EdgeInsets.only(bottom: 4.0),
                            child: Focus(
                              onFocusChange: (hasFocus) {
                                focused = hasFocus;
                                if (hasFocus) {
                                  HotKeys.instance.disableSpaceHotKey();
                                } else {
                                  HotKeys.instance.enableSpaceHotKey();
                                }
                              },
                              child: TextField(
                                controller: controllers[0],
                                scrollPhysics: NeverScrollableScrollPhysics(),
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9]|.')),
                                ],
                                onChanged: (value) {
                                  playback.setRate(
                                    double.tryParse(value) ?? playback.rate,
                                  );
                                },
                                textAlign: TextAlign.center,
                                textAlignVertical: TextAlignVertical.center,
                                style: Theme.of(context).textTheme.headline4,
                                decoration: inputDecoration(
                                  context,
                                  '',
                                ).copyWith(
                                  contentPadding: EdgeInsets.only(
                                    left: 4.0,
                                    right: 4.0,
                                    bottom: 14.0,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16.0),
                        ],
                      ),
                      const SizedBox(height: 8.0),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(width: 8.0),
                          IconButton(
                            padding: EdgeInsets.all(8.0),
                            onPressed: () => playback.setPitch(1.0),
                            iconSize: 20.0,
                            splashRadius: 18.0,
                            tooltip: Language.instance.RESET_PITCH,
                            icon: Icon(FluentIcons.pulse_20_filled),
                          ),
                          const SizedBox(width: 8.0),
                          Expanded(
                            child: ScrollableSlider(
                              min: 0.5,
                              max: 1.5,
                              value: playback.pitch.clamp(0.5, 1.5),
                              onScrolledUp: () {
                                playback.setPitch(
                                  (playback.pitch + 0.05).clamp(0.5, 1.5),
                                );
                              },
                              onScrolledDown: () {
                                playback.setPitch(
                                  (playback.pitch - 0.05).clamp(0.5, 1.5),
                                );
                              },
                              onChanged: (value) {
                                playback.setPitch(value);
                              },
                            ),
                          ),
                          const SizedBox(width: 16.0),
                          Container(
                            width: 42.0,
                            height: 32.0,
                            padding: EdgeInsets.only(bottom: 4.0),
                            child: Focus(
                              onFocusChange: (hasFocus) {
                                focused = hasFocus;
                                if (hasFocus) {
                                  HotKeys.instance.disableSpaceHotKey();
                                } else {
                                  HotKeys.instance.enableSpaceHotKey();
                                }
                              },
                              child: TextField(
                                controller: controllers[1],
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9]|.')),
                                ],
                                onChanged: (value) {
                                  playback.setPitch(
                                    double.tryParse(value) ?? playback.pitch,
                                  );
                                },
                                scrollPhysics: NeverScrollableScrollPhysics(),
                                textAlign: TextAlign.center,
                                textAlignVertical: TextAlignVertical.center,
                                style: Theme.of(context).textTheme.headline4,
                                decoration: inputDecoration(
                                  context,
                                  '',
                                ).copyWith(
                                  contentPadding: EdgeInsets.only(
                                    left: 4.0,
                                    right: 4.0,
                                    bottom: 14.0,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16.0),
                        ],
                      ),
                      const SizedBox(height: 8.0),
                    ],
                  ),
                ),
                builder: (context, value, child) => Transform.translate(
                  offset: Offset(0, value as double),
                  child: Card(
                    color: Theme.of(context).cardColor,
                    elevation: 8.0,
                    margin: widget.x == null
                        ? EdgeInsets.all(16.0)
                        : EdgeInsets.only(
                            right: MediaQuery.of(context).size.width -
                                (widget.x ?? 0.0) -
                                64.0 -
                                240.0,
                            bottom: 16.0,
                          ),
                    child: Container(
                      width: 240.0,
                      height: 156.0,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        onWillPop: () async {
          widget.onPop();
          setState(() {
            end = 156.0;
          });
          await Future.delayed(const Duration(milliseconds: 100));
          return Future.value(true);
        },
      ),
    );
  }
}

extension on Color {
  bool get isDark => (0.299 * red) + (0.587 * green) + (0.114 * blue) < 128.0;
}
