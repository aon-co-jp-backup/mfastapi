cmake_minimum_required(VERSION 3.16)
project(fastapim C)
# 移植用C実装(Windows / Linux / macOS / BSD / Android / iOS)。MojoはLinux・macOSで別途ビルドする。
add_library(fastapim SHARED c/fastapim_cabi.c)
set_target_properties(fastapim PROPERTIES C_VISIBILITY_PRESET hidden)
if(IOS)
  # iOSは動的ライブラリを同梱しにくいため静的ライブラリも作る(アプリへリンクして利用)。
  add_library(fastapim_static STATIC c/fastapim_cabi.c)
endif()
