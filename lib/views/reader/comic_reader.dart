// @dart=2.9

import 'dart:convert';
import 'dart:typed_data';

import 'package:battery/battery.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:common_utils/common_utils.dart';
import 'package:connectivity/connectivity.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_dmzj/app/api.dart';
import 'package:flutter_dmzj/app/app_setting.dart';
import 'package:flutter_dmzj/app/config_helper.dart';
import 'package:flutter_dmzj/app/screen.dart';
import 'package:flutter_dmzj/app/user_helper.dart';
import 'package:flutter_dmzj/app/user_info.dart';
import 'package:flutter_dmzj/app/utils.dart';
import 'package:flutter_dmzj/models/comic/comic_chapter_view_point.dart';
import 'package:flutter_dmzj/models/comic/comic_detail_model.dart';
import 'package:flutter_dmzj/models/comic/comic_web_chapter_detail.dart';
import 'package:flutter_dmzj/protobuf/comic/detail_response.pb.dart';
import 'package:flutter_dmzj/sql/comic_history.dart';
import 'package:flutter_dmzj/views/other/platform_methods.dart';
import 'package:flutter_dmzj/views/reader/comic_tc.dart';
import 'package:flutter_dmzj/widgets/GestureZoomBox.dart';
import 'package:flutter_dmzj/widgets/comic_view.dart';
import 'package:flutter_dmzj/widgets/positioned_list/item_positions_listener.dart';
import 'package:flutter_dmzj/widgets/positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_easyrefresh/easy_refresh.dart';
import 'package:flutter_easyrefresh/material_footer.dart';
import 'package:flutter_easyrefresh/material_header.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:preload_page_view/preload_page_view.dart';
import 'package:provider/provider.dart';
import 'package:share/share.dart';

class ComicReaderPage extends StatefulWidget {
  final int comicId;
  final List<ComicDetailChapterInfoResponse> chapters;
  final ComicDetailChapterInfoResponse item;
  final String comicTitle;
  bool subscribe;

  ComicReaderPage(
      this.comicId, this.comicTitle, this.chapters, this.item, this.subscribe,
      {Key key})
      : super(key: key);

  @override
  _ComicReaderPageState createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends State<ComicReaderPage> {
  ComicDetailChapterInfoResponse _currentItem;
  Battery _battery = PlatformBattery();
  Connectivity _connectivity = Connectivity();
  String _batteryStr = "-%";
  String _networkState = "";
  double _expandWidth = 800;

  @override
  void initState() {
    super.initState();
    if (ConfigHelper.getComicShowStatusBar()) {
      SystemChrome.setEnabledSystemUIOverlays([]);
    }
    if (Utils.isSupportScreen) {
      //亮度信息
      if (!ConfigHelper.getComicSystemBrightness()) {
        Screen.setBrightness(ConfigHelper.getComicBrightness());
      }
      Screen.keepOn(ConfigHelper.getComicWakelock());
    }

    _currentItem = widget.item;

    if (Utils.isMobilePlatform) {
      initConnectivity();
    }

    _battery.batteryLevel.then((e) {
      setState(() {
        _batteryStr = e.toString() + "%";
      });
    });
    _battery.onBatteryStateChanged.listen((BatteryState state) async {
      var e = await _battery.batteryLevel;
      setState(() {
        _batteryStr = e.toString() + "%";
      });
    });

    initScrollPosition();

    loadData();
  }

  // https://github.com/google/flutter.widgets/blob/master/packages/scrollable_positioned_list/example/lib/main.dart
  void initScrollPosition() {
    itemPositionsListener.itemPositions.addListener(() {
      var positions = itemPositionsListener.itemPositions.value;
      ItemPosition min;
      ItemPosition max;
      if (positions.isNotEmpty) {
        min = positions
            .where((ItemPosition position) => position.itemTrailingEdge > 0)
            .reduce((ItemPosition min, ItemPosition position) =>
                position.itemTrailingEdge < min.itemTrailingEdge
                    ? position
                    : min);
        max = positions
            .where((ItemPosition position) => position.itemLeadingEdge < 1)
            .reduce((ItemPosition max, ItemPosition position) =>
                position.itemLeadingEdge > max.itemLeadingEdge
                    ? position
                    : max);

        var newIndex = min.index + 1;
        _selectOffset = min.itemTrailingEdge;
        //print("positionChanged: min:$min, width:$width, height:$height, newIndex:$newIndex, _selectOffset:$_selectOffset");
        if (_selectIndex != newIndex) {
          setState(() {
            _selectIndex = newIndex;
          });
        }
      }
    });
  }

  @override
  void setState(fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIOverlays(SystemUiOverlay.values);
    if (Utils.isSupportScreen) {
      Screen.keepOn(false);
    }
    int page = 1;
    if (true) {
      print(_selectIndex);
      page = _selectIndex;
      if (page > _detail.picnum) {
        page = _detail.picnum;
      }
    }

    print("current page:$page, _selectOffset:$_selectOffset");
    ComicHistoryProvider.getItem(widget.comicId).then((historyItem) async {
      if (historyItem != null) {
        historyItem.chapter_id = _currentItem.chapterId;
        historyItem.page = page.toDouble();
        historyItem.offset = _selectOffset;
        await ComicHistoryProvider.update(historyItem);
      } else {
        await ComicHistoryProvider.insert(ComicHistory(widget.comicId,
            _currentItem.chapterId, page.toDouble(), _selectOffset, 1));
      }
      Utils.changHistory.fire(widget.comicId);
    });

    UserHelper.comicAddComicHistory(widget.comicId, _currentItem.chapterId,
        page: page);
    super.dispose();
  }

  bool _showControls = false;
  bool _showChapters = false;
  int _selectIndex = 1;
  double _selectOffset = 0.0;
  int _pendingIndex = 1;
  double _pendingOffset = 0.0;

  bool _expand;

  bool get comicVerticalMode => context.comicVerticalMode;

  var maxConstraints = BoxConstraints(maxWidth: 800);

  @override
  Widget build(BuildContext context) {
    if (_expand == null) {
      _expand = MediaQuery.of(context).size.width < _expandWidth;
    }
    return Scaffold(
      backgroundColor: Colors.black,
      floatingActionButton: MediaQuery.of(context).size.width > _expandWidth
          ? FloatingActionButton(
              heroTag: 'comic',
              child: Icon(_expand ? Icons.fullscreen_exit : Icons.zoom_out_map),
              onPressed: () {
                setState(() {
                  _expand = !_expand;
                });
              })
          : null,
      body: Center(
        child: Container(
          constraints: _expand ? null : maxConstraints,
          child: Stack(
            children: <Widget>[
              !_loading ? _isError ? Container(
                child: Center(
                  child: InkWell(
                    onTap: (){
                      loadData();
                    },
                    child: Text("点击重试", style: TextStyle(color: Colors.white),),
                  ),
                ),
              ) :
                   (comicVerticalMode
                      ? createVerticalReader()
                      : createHorizontalReader())
                  : Center(
                      child: CircularProgressIndicator(),
                    ),
              _createReadStatus(),
              _createTurnPage1(),
              _createTurnPage2(),
              //顶部
              _createTopWidget(),
              //底部
              _createBottom(),
              //右侧章节选择
              createLeftChapter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createReadStatus() {
    return Positioned(
      child: Provider.of<AppSetting>(context).comicReadShowstate
          ? Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.max,
            children: [
              Container(
                  padding: EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                  color: Color.fromARGB(255, 34, 34, 34),
                  child: Text(Utils.getCurrentTime(), style: TextStyle(color: Colors.white, fontSize: 12))),
              Container(
                padding: EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                color: Color.fromARGB(255, 34, 34, 34),
                child: Text(
                  _loading
                      ? "${_currentItem.chapterTitle}  加载中 WIFI  100%电量"
                      : "${_currentItem.chapterTitle}  $_selectIndex/${_detail.page_url.length}  $_networkState  $_batteryStr 电量",
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          )
          : Container(),
      bottom: 0,
      right: 0,
      left: 0,
    );
  }

  Widget _createTurnPage1() {
    return comicVerticalMode
        ? Positioned(child: Container())
        : Positioned(
            left: 0,
            width: 80,
            top: 0,
            bottom: 0,
            child: InkWell(
              onTap: () {
                if (Provider.of<AppSetting>(context, listen: false)
                    .comicReadReverse) {
                  previousPage();
                } else {
                  nextPage();
                }
              },
              child: Container(),
            ),
          );
  }

  Widget _createTurnPage2() {
    return comicVerticalMode
        ? Positioned(child: Container())
        : Positioned(
            right: 0,
            width: 80,
            top: 0,
            bottom: 0,
            child: InkWell(
              onTap: () {
                if (Provider.of<AppSetting>(context, listen: false)
                    .comicReadReverse) {
                  nextPage();
                } else {
                  previousPage();
                }
              },
              child: Container(),
            ),
          );
  }

  // 顶部
  Widget _createTopWidget() {
    return AnimatedPositioned(
      duration: Duration(milliseconds: 200),
      top: _showControls ? 0 : -100,
      left: 0,
      right: 0,
      child: Container(
            padding: EdgeInsets.only(
                top: Provider.of<AppSetting>(context).comicReadShowStatusBar
                    ? 0
                    : MediaQuery.of(context).padding.top),
            child: Material(
                color: Color.fromARGB(255, 34, 34, 34),
                child: ListTile(
                  dense: true,
                  title: Text(
                    widget.comicTitle,
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    _currentItem.chapterTitle,
                    style: TextStyle(color: Colors.white),
                  ),
                  leading: BackButton(
                    color: Colors.white,
                  ),
                  trailing: IconButton(
                      icon: Icon(
                        Icons.share,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        Share.share(
                            '${widget.comicTitle}-${_currentItem.chapterTitle}\r\nhttps://m.dmzj.com/view/${widget.comicId}/${_currentItem.chapterId}.html');
                      }),
                )),
          )
    );
  }

  // 底部
  Widget _createBottom() {
    return AnimatedPositioned(
      duration: Duration(milliseconds: 200),
      bottom: _showControls ? 0 : -140,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        color: Color.fromARGB(255, 34, 34, 34),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                ButtonTheme(
                  minWidth: 10,
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: TextButton(
                    onPressed: previousChapter,
                    child: Text(
                      "上一话",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                Expanded(
                  child: !_loading
                      ? comicVerticalMode
                          ? Slider(
                              value: _selectIndex.toDouble(),
                              max: _detail.picnum.toDouble(),
                              onChanged: (e) {
                                itemScrollController.jumpTo(index: e.toInt());
                              },
                            )
                          : Slider(
                              value: _selectIndex >= 1
                                  ? _selectIndex.toDouble()
                                  : 0,
                              max: _detail.picnum.toDouble(),
                              onChanged: (e) {
                                setState(() {
                                  _selectIndex = e.toInt();
                                  _pageController.jumpToPage(e.toInt() + 1);
                                });
                              },
                            )
                      : Text(
                          "加载中",
                          style: TextStyle(color: Colors.white),
                        ),
                ),
                ButtonTheme(
                  minWidth: 10,
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: TextButton(
                    onPressed: nextChapter,
                    child: Text(
                      "下一话",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                )
              ],
            ),
            Row(
              children: <Widget>[
                Provider.of<AppUserInfo>(context).isLogin && widget.subscribe
                    ? createButton(
                        "已订阅",
                        Icons.favorite,
                        onTap: () async {
                          if (await UserHelper.comicSubscribe(widget.comicId,
                              cancel: true)) {
                            setState(() {
                              widget.subscribe = false;
                            });
                          }
                        },
                      )
                    : createButton(
                        "订阅",
                        Icons.favorite_border,
                        onTap: () async {
                          if (await UserHelper.comicSubscribe(widget.comicId)) {
                            setState(() {
                              widget.subscribe = true;
                            });
                          }
                        },
                      ),
                createButton("设置", Icons.settings, onTap: openSetting),
                createButton(
                    _detail != null ? "吐槽(${_viewPoints.length})" : "吐槽",
                    Icons.chat_bubble_outline,
                    onTap: openTCPage),
                createButton("章节", Icons.format_list_bulleted, onTap: () {
                  setState(() {
                    _showChapters = true;
                  });
                }),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget createLeftChapter() {
    return AnimatedPositioned(
      duration: Duration(milliseconds: 200),
      width: 200,
      top: 0,
      bottom: 0,
      right: _showChapters ? 0 : -200,
      child: Container(
          color: Color.fromARGB(255, 24, 24, 24),
          padding: EdgeInsets.only(
              top: Provider.of<AppSetting>(context).comicReadShowStatusBar
                  ? 0
                  : MediaQuery.of(context).padding.top),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    "目录(${widget.chapters.length})",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  )),
              Expanded(
                child: ListView(
                  children: widget.chapters
                      .map((f) => ListTile(
                            dense: true,
                            onTap: () async {
                              if (f != _currentItem) {
                                setState(() {
                                  _currentItem = f;
                                  _showChapters = false;
                                  _showControls = false;
                                });

                                await loadData();
                              }
                            },
                            title: Text(
                              f.chapterTitle,
                              style: TextStyle(
                                  color: f == _currentItem
                                      ? Theme.of(context).accentColor
                                      : Colors.white),
                            ),
                            subtitle: Text(
                              "更新于" +
                                  TimelineUtil.format(
                                    int.parse(f.updatetime.toString()) * 1000,
                                    locale: 'zh',
                                  ),
                              style: TextStyle(color: Colors.grey),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],
          )),

    );
  }

  void nextPage() async {
    if (_pageController.page == 1) {
      await previousChapter();
      setState(() {
        _selectIndex = _detail.page_url.length;
        _pageController = PreloadPageController(initialPage: _selectIndex + 1);
        print('_selectIndex:' + _selectIndex.toString());
        print('page:${_selectIndex + 1}');
      });
    } else {
      setState(() {
        int newPage;
        if (_pageController.page.toInt() > _selectIndex) {
          newPage = _pageController.page.toInt() - 1;
        } else {
          newPage = _selectIndex - 1;
        }
        _pageController.animateToPage(newPage, duration: Duration(milliseconds: 500), curve: Curves.easeInOut);
      });
    }
  }

  void previousPage() {
    if (_pageController.page > _detail.page_url.length) {
      nextChapter();
    } else {
      setState(() {
        _pageController.animateToPage(_selectIndex + 1,
            duration: Duration(milliseconds: 500), curve: Curves.easeInOut);
      });
    }
  }

  Widget createButton(String text, IconData icon, {Function onTap}) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Column(
              children: <Widget>[
                Icon(icon, color: Colors.white),
                SizedBox(
                  height: 4,
                ),
                Text(
                  text,
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 打开吐槽详情页
  void openTCPage() {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (BuildContext context) => ComicTCPage(
                _viewPoints, widget.comicId, _currentItem.chapterId)));
  }

  PreloadPageController _pageController = PreloadPageController(initialPage: 1);

  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemPositionsListener itemPositionsListener =
      ItemPositionsListener.create();

  Widget createHorizontalReader() {
    return GestureZoomBox(
      onPressed: () {
        print("GestureZoomBox onPressed::::");
        setState(() {
          if (_showChapters) {
            _showChapters = false;
            return;
          }
          _showControls = !_showControls;
        });
      },
      maxScale: 5.0,
      doubleTapScale: 2.0,
      child: Container(
        color: Colors.black,
        child: ComicView.builder(
          reverse: Provider.of<AppSetting>(context).comicReadReverse,
          builder: (BuildContext context, int index) {
            if (index > 0 && index <= _detail.page_url.length) {
              return PhotoViewGalleryPageOptions(
                filterQuality: FilterQuality.high,
                imageProvider: CachedNetworkImageProvider(
                  _detail.page_url[index - 1],
                  headers: {"Referer": "http://www.dmzj.com/"},
                ),
                initialScale: PhotoViewComputedScale.contained,
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4.1,
              );
            } else {
              return PhotoViewGalleryPageOptions.customChild(
                  child: getExtraPage(index));
            }
          },
          gaplessPlayback: true,
          itemCount: _detail.page_url.length + 3,
          loadingBuilder: (context, event) {
            return Center(
              child: CircularProgressIndicator(),
            );
          },
          loadFailedChild: Center(
            child: Text("出错啦"),
          ),
          pageController: _pageController,
          onPageChanged: (i) {
            if (i == _detail.page_url.length + 2) {
              nextChapter();
              return;
            }
            if (i == 0 && !_loading) {
              previousChapter();
              return;
            }
            if (i < _detail.page_url.length + 1) {
              setState(() {
                _selectIndex = i;
              });
            }
            print('_selectIndex:' + _selectIndex.toString());
            print('page:$i');
          },
        ),
      ),
    );
  }

  Widget getExtraPage(int index) {
    if (index == 0) {
      return Center(
        child: Text(
            widget.chapters.indexOf(_currentItem) == 0 ? "前面没有了" : "上一章",
            style: TextStyle(color: Colors.grey)),
      );
    }
    if (index == _detail.page_url.length + 1) {
      return createTucao(24);
    }
    if (index == _detail.page_url.length + 2) {
      return Center(
        child: Text(
            widget.chapters.indexOf(_currentItem) == widget.chapters.length - 1
                ? "后面没有了"
                : "下一章",
            style: TextStyle(color: Colors.grey)),
      );
    }
    return Center(
      child: Text("出错啦"),
    );
  }

  Widget createVerticalReader() {
    return GestureZoomBox(
      onPressed: () {
        setState(() {
          if (_showChapters) {
            _showChapters = false;
            return;
          }
          _showControls = !_showControls;
        });
      },
      maxScale: 5.0,
      doubleTapScale: 2.0,
      child: ScrollablePositionedList.separated(
          itemCount: _detail.page_url.length + 2,
          itemScrollController: itemScrollController,
          itemPositionsListener: itemPositionsListener,
          initialScrollIndex: _pendingIndex,
          initialAlignment: _pendingOffset,
          scrollDirection: Axis.vertical,
          resolveGestureConflict: true,
          separatorBuilder: (ctx, i) => Container(
                height: 10,
              ),
          itemBuilder: (ctx, i) {
            if (i == _detail.page_url.length + 1) {
              return createNextChapter();
            } else if (i == _detail.page_url.length) {
              return createTucao(24);
            } else {
              var f = _detail.page_url[i];
              return Container(
                color: Colors.black,
                padding: EdgeInsets.only(bottom: 0),
                child: CachedNetworkImage(
                    imageUrl: f,
                    httpHeaders: {"Referer": "http://www.dmzj.com/"},
                    fit: BoxFit.cover,
                    placeholder: (ctx, i) => Container(
                          height: 400,
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                    filterQuality: FilterQuality.high),
              );
            }
          }),
    );
  }

  Widget createNextChapter() {
    return InkWell(
      onTap: () => nextChapter(),
      child: Container(
        height: 160,
        child: Center(
          child: Text(
            "下一章",
            style: TextStyle(color: Colors.white, fontSize: 20),
          ),
        ),
      ),
    );
  }

  Widget createTucao(int count) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: EdgeInsets.all(8),
            child: Text("本章吐槽",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white,
                )),
          ),
          Wrap(
            children: _viewPoints
                .take(count)
                .map<Widget>((f) => createTucaoItem(f))
                .toList(),
          ),
          SizedBox(height: 12),
          Center(
            child: OutlinedButton(
                style: ButtonStyle(
                  side: MaterialStateProperty.all(
                      BorderSide(color: Colors.white.withOpacity(0.6))),
                ),
                onPressed: openTCPage,
                child: Text(
                  "查看更多(${_viewPoints.length})",
                  style: TextStyle(color: Colors.white),
                )),
          )
        ],
      ),
    );
  }

  Widget createTucaoItem(ComicChapterViewPoint item) {
    return Padding(
      padding: EdgeInsets.all(4),
      child: InkWell(
        onTap: () async {
          var result = await UserHelper.comicLikeViewPoint(item.id);
          if (result) {
            setState(() {
              item.num++;
            });
          }
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.withOpacity(0.4)),
              borderRadius: BorderRadius.circular(16)),
          child: Text(
            item.content,
            style: TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }

  void openSetting() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Material(
          color: Color.fromARGB(255, 34, 34, 34),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Utils.isMobilePlatform
                    ? SwitchListTile(
                        title: Text(
                          "使用系统亮度",
                          style: TextStyle(color: Colors.white),
                        ),
                        value: Provider.of<AppSetting>(context)
                            .comicSystemBrightness,
                        onChanged: (e) {
                          Provider.of<AppSetting>(context, listen: false)
                              .changeComicSystemBrightness(e);
                        })
                    : Container(),
                !Provider.of<AppSetting>(context).comicSystemBrightness
                    ? Row(
                        children: <Widget>[
                          SizedBox(width: 12),
                          Icon(
                            Icons.brightness_2,
                            color: Colors.white,
                            size: 18,
                          ),
                          Expanded(
                              child: Slider(
                                  value: Provider.of<AppSetting>(context)
                                      .comicBrightness,
                                  max: 1,
                                  min: 0.01,
                                  onChanged: (e) {
                                    Screen.setBrightness(e);
                                    Provider.of<AppSetting>(context,
                                            listen: false)
                                        .changeBrightness(e);
                                  })),
                          Icon(Icons.brightness_5,
                              color: Colors.white, size: 18),
                          SizedBox(width: 12),
                        ],
                      )
                    : Container(),
                SwitchListTile(
                    title: Text(
                      "使用网页API",
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      "网页部分单行本不分页",
                      style: TextStyle(color: Colors.grey),
                    ),
                    value: Provider.of<AppSetting>(context).comicWebApi,
                    onChanged: (e) {
                      Provider.of<AppSetting>(context, listen: false)
                          .changeComicWebApi(e);
                      loadData();
                    }),
                SwitchListTile(
                    title: Text(
                      "竖向阅读",
                      style: TextStyle(color: Colors.white),
                    ),
                    value: Provider.of<AppSetting>(context).comicVerticalMode,
                    onChanged: (e) {
                      Provider.of<AppSetting>(context, listen: false)
                          .changeComicVertical(e);
                      //Navigator.pop(context);
                    }),
                !Provider.of<AppSetting>(context).comicVerticalMode
                    ? SwitchListTile(
                        title: Text(
                          "日漫模式",
                          style: TextStyle(color: Colors.white),
                        ),
                        value:
                            Provider.of<AppSetting>(context).comicReadReverse,
                        onChanged: (e) {
                          Provider.of<AppSetting>(context, listen: false)
                              .changeReadReverse(e);
                        })
                    : Container(),
                Utils.isMobilePlatform
                    ? SwitchListTile(
                        title: Text(
                          "屏幕常亮",
                          style: TextStyle(color: Colors.white),
                        ),
                        value: Provider.of<AppSetting>(context).comicWakelock,
                        onChanged: (e) {
                          Screen.keepOn(e);
                          Provider.of<AppSetting>(context, listen: false)
                              .changeComicWakelock(e);
                        })
                    : Container(),
                SwitchListTile(
                    title: Text(
                      "全屏阅读",
                      style: TextStyle(color: Colors.white),
                    ),
                    value:
                        Provider.of<AppSetting>(context).comicReadShowStatusBar,
                    onChanged: (e) {
                      Provider.of<AppSetting>(context, listen: false)
                          .changeComicReadShowStatusBar(e);
                      SystemChrome.setEnabledSystemUIOverlays(
                          e ? [] : SystemUiOverlay.values);
                    }),
                SwitchListTile(
                    title: Text(
                      "显示状态信息",
                      style: TextStyle(color: Colors.white),
                    ),
                    value: Provider.of<AppSetting>(context).comicReadShowstate,
                    onChanged: (e) {
                      Provider.of<AppSetting>(context, listen: false)
                          .changeComicReadShowState(e);
                    }),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _loading = false;
  bool _isError = false;
  ComicWebChapterDetail _detail;
  DefaultCacheManager _cacheManager = DefaultCacheManager();

  Future loadData({bool isPrevious = false}) async {
    try {
      if (_loading) {
        return;
      }
      setState(() {
        _loading = true;
        _isError = false;
      });
      var api = Api.comicChapterDetail(widget.comicId, _currentItem.chapterId);

      if (ConfigHelper.getComicWebApi()) {
        api = Api.comicWebChapterDetail(widget.comicId, _currentItem.chapterId);
      }
      Uint8List responseBody;
      try {
        var response = await http.get(Uri.parse(api));
        responseBody = response.bodyBytes;
      } catch (e) {
        var file = await _cacheManager.getFileFromCache(api);
        if (file != null) {
          responseBody = await file.file.readAsBytes();
        }
      }

      var responseStr = utf8.decode(responseBody);
      var jsonMap = jsonDecode(responseStr);

      ComicWebChapterDetail detail = ComicWebChapterDetail.fromJson(jsonMap);
      var historyItem = await ComicHistoryProvider.getItem(widget.comicId);
      if (historyItem != null &&
          historyItem.chapter_id == _currentItem.chapterId) {
        var page = historyItem.page.toInt();
        var offset = historyItem.offset ?? 0;
        if (page > detail.page_url.length) {
          page = detail.page_url.length;
        }
        _pageController = new PreloadPageController(initialPage: page);
        setState(() {
          _selectIndex = page;
          _pendingIndex = page;
          _pendingOffset = offset;
        });
        // _pageController.=;
      } else {
        var initialPage = isPrevious ? detail.page_url.length: 1;
        _pageController = new PreloadPageController(initialPage: initialPage);
        setState(() {
          _selectIndex = initialPage;
          _pendingIndex = 0;
          _pendingOffset = 0;
        });
      }

      setState(() {
        _detail = detail;
      });
      await _cacheManager.putFile(api, responseBody);
      await loadViewPoint();

      //ConfigHelper.setComicHistory(widget.comicId, _currentItem.chapter_id);
      await UserHelper.comicAddComicHistory(
          widget.comicId, _currentItem.chapterId);
    } catch (e) {
      print(e);
      setState(() {
        _isError = true;
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  List<ComicChapterViewPoint> _viewPoints = [];

  Future loadViewPoint() async {
    try {
      setState(() {
        _viewPoints = [];
      });
      var response = await http.get(Uri.parse(
          Api.comicChapterViewPoint(widget.comicId, _currentItem.chapterId)));

      List jsonMap = jsonDecode(response.body);
      List<ComicChapterViewPoint> ls =
          jsonMap.map((f) => ComicChapterViewPoint.fromJson(f)).toList();
      ls.sort((a, b) => b.num.compareTo(a.num));
      setState(() {
        _viewPoints = ls;
      });
    } catch (e) {
      print(e);
    }
  }

  void nextChapter() async {
    if (widget.chapters.indexOf(_currentItem) == widget.chapters.length - 1) {
      Fluttertoast.showToast(msg: '已经是最后一章了');
      return;
    }
    setState(() {
      _currentItem = widget.chapters[widget.chapters.indexOf(_currentItem) + 1];
    });
    await loadData();
  }

  void previousChapter() async {
    if (widget.chapters.indexOf(_currentItem) == 0) {
      Fluttertoast.showToast(msg: '已经是最前面一章了');
      return;
    }
    setState(() {
      _currentItem = widget.chapters[widget.chapters.indexOf(_currentItem) - 1];
    });
    await loadData(isPrevious: true);
  }

  void initConnectivity() {
    _connectivity.checkConnectivity().then((e) {
      var str = "";
      if (e == ConnectivityResult.mobile) {
        str = "移动网络";
      } else if (e == ConnectivityResult.wifi) {
        str = "WIFI";
      } else if (e == ConnectivityResult.none) {
        str = "无网络";
      } else {
        str = "未知网络";
      }
      setState(() {
        _networkState = str;
      });
    });
    _connectivity.onConnectivityChanged.listen((e) {
      var str = "";
      if (e == ConnectivityResult.mobile) {
        str = "移动网络";
      } else if (e == ConnectivityResult.wifi) {
        str = "WIFI";
      } else if (e == ConnectivityResult.none) {
        str = "无网络";
      } else {
        str = "未知网络";
      }
      setState(() {
        _networkState = str;
      });
    });
  }
}
