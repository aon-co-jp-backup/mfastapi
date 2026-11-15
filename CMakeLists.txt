cmake_minimum_required(VERSION 3.16)
project(mfastapi C)
# 移植用C実装(Windows / Linux / macOS / BSD / Android / iOS)。MojoはLinux・macOSで別途ビルドする。
add_library(mfastapi SHARED c/mfastapi_cabi.c)
set_target_properties(mfastapi PROPERTIES C_VISIBILITY_PRESET hidden)
if(IOS)
  # iOSは動的ライブラリを同梱しにくいため静的ライブラリも作る(アプリへリンクして利用)。
  add_library(mfastapi_static STATIC c/mfastapi_cabi.c)
endif()
