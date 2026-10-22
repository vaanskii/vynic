cmake_minimum_required(VERSION 3.14)
project(vynic_windows_spooler_tests LANGUAGES CXX)

# Standalone and portable: this target never links Winspool or sends a job.
add_executable(windows_spooler_test
  "windows_spooler_test.cpp"
  "../runner/windows_spooler.cpp"
)
target_compile_features(windows_spooler_test PRIVATE cxx_std_17)
if(MSVC)
  target_compile_options(windows_spooler_test PRIVATE /W4 /WX /EHsc)
else()
  target_compile_options(windows_spooler_test PRIVATE -Wall -Wextra -Werror)
endif()
enable_testing()
add_test(NAME windows_spooler_fake_api COMMAND windows_spooler_test)

# Opt-in only. This console harness creates a message-only HWND, uses the real
# channel/codec, and enumerates queues. All submitRaw fixtures contain no payload
# or an empty payload; no print document can be opened or submitted.
option(VYNIC_BUILD_READ_ONLY_CHANNEL_TEST
  "Build the read-only Win32 channel harness from an existing Flutter SDK cache"
  OFF
)
if(VYNIC_BUILD_READ_ONLY_CHANNEL_TEST)
  if(NOT WIN32)
    message(FATAL_ERROR "The read-only channel harness requires Windows")
  endif()
  set(VYNIC_FLUTTER_CPP_WRAPPER "" CACHE PATH
    "Existing Flutter cpp_client_wrapper directory (no SDK download)"
  )
  get_filename_component(_vynic_engine_default
    "${VYNIC_FLUTTER_CPP_WRAPPER}" DIRECTORY
  )
  set(VYNIC_FLUTTER_ENGINE_DIR "${_vynic_engine_default}" CACHE PATH
    "Existing Flutter C API headers, flutter_windows.dll.lib and runtime DLL"
  )
  foreach(_vynic_sdk_file
    "${VYNIC_FLUTTER_CPP_WRAPPER}/include/flutter/binary_messenger.h"
    "${VYNIC_FLUTTER_CPP_WRAPPER}/standard_codec.cc"
    "${VYNIC_FLUTTER_CPP_WRAPPER}/core_implementations.cc"
    "${VYNIC_FLUTTER_CPP_WRAPPER}/byte_buffer_streams.h"
    "${VYNIC_FLUTTER_CPP_WRAPPER}/binary_messenger_impl.h"
    "${VYNIC_FLUTTER_CPP_WRAPPER}/texture_registrar_impl.h"
    "${VYNIC_FLUTTER_ENGINE_DIR}/flutter_messenger.h"
    "${VYNIC_FLUTTER_ENGINE_DIR}/flutter_texture_registrar.h"
    "${VYNIC_FLUTTER_ENGINE_DIR}/flutter_windows.dll.lib"
    "${VYNIC_FLUTTER_ENGINE_DIR}/flutter_windows.dll"
  )
    if(NOT EXISTS "${_vynic_sdk_file}")
      message(FATAL_ERROR "Required existing Flutter cache file missing: ${_vynic_sdk_file}")
    endif()
  endforeach()

  # EngineMethodResult's one-shot ReplyManager lives in core_implementations.cc.
  # Compile that cached implementation; a test substitute would conceal its
  # lifetime behavior. Its unused messenger/texture definitions require the
  # existing C API import library/DLL, but the harness never creates an engine.
  add_library(vynic_cached_flutter_wrapper STATIC
    "${VYNIC_FLUTTER_CPP_WRAPPER}/standard_codec.cc"
    "${VYNIC_FLUTTER_CPP_WRAPPER}/core_implementations.cc"
  )
  target_compile_features(vynic_cached_flutter_wrapper PUBLIC cxx_std_17)
  target_include_directories(vynic_cached_flutter_wrapper SYSTEM PUBLIC
    "${VYNIC_FLUTTER_CPP_WRAPPER}/include"
    "${VYNIC_FLUTTER_ENGINE_DIR}"
  )
  if(MSVC)
    target_compile_options(vynic_cached_flutter_wrapper PRIVATE /EHsc)
  endif()
  target_link_libraries(vynic_cached_flutter_wrapper PUBLIC
    "${VYNIC_FLUTTER_ENGINE_DIR}/flutter_windows.dll.lib"
  )

  add_executable(windows_spooler_channel_test
    "windows_spooler_channel_test.cpp"
    "../runner/windows_spooler.cpp"
    "../runner/windows_spooler_native.cpp"
    "../runner/windows_spooler_channel.cpp"
  )
  target_compile_features(windows_spooler_channel_test PRIVATE cxx_std_17)
  target_compile_definitions(windows_spooler_channel_test PRIVATE
    NOMINMAX UNICODE _UNICODE
  )
  if(MSVC)
    target_compile_options(windows_spooler_channel_test PRIVATE /W4 /WX /EHsc)
  endif()
  target_link_libraries(windows_spooler_channel_test PRIVATE
    vynic_cached_flutter_wrapper winspool user32
  )
  add_custom_command(TARGET windows_spooler_channel_test POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "${VYNIC_FLUTTER_ENGINE_DIR}/flutter_windows.dll"
      "$<TARGET_FILE_DIR:windows_spooler_channel_test>/flutter_windows.dll"
  )
  add_test(NAME windows_spooler_read_only_channel
    COMMAND windows_spooler_channel_test
  )
  set_tests_properties(windows_spooler_read_only_channel PROPERTIES TIMEOUT 30)
endif()
