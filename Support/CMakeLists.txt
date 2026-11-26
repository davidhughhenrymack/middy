cmake_minimum_required(VERSION 3.16)
project(MiddyLink LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include("${ABLETON_LINK_SOURCE}/AbletonLinkConfig.cmake")
include("${ABLETON_LINK_SOURCE}/extensions/abl_link/abl_link.cmake")
