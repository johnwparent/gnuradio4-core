add_library(ut-benchmark INTERFACE benchmark.hpp)
add_library(gnuradio4::ut-benchmark ALIAS ut-benchmark)
target_include_directories(ut-benchmark INTERFACE $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
                                                  $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>)
gr_install_artifact(TARGETS ut-benchmark EXPORT gnuradio4Targets COMPONENT DEVELOP)
gr_install_artifact(FILES ${CMAKE_CURRENT_SOURCE_DIR}/benchmark.hpp DESTINATION ${CMAKE_INSTALL_INCLUDEDIR} COMPONENT DEVELOP)

function(append_compiler_flags TARGET_NAME)
  set(FLAGS_COMMON -Wall)
  if(EMSCRIPTEN)
    set(FLAGS_SPECIAL "")
  else()
    set(FLAGS_SPECIAL -march=native)
  endif()

  target_compile_options(${TARGET_NAME} PRIVATE ${FLAGS_COMMON} ${FLAGS_SPECIAL})
  target_link_options(
    ${TARGET_NAME}
    PRIVATE
    ${FLAGS_COMMON}
    ${FLAGS_SPECIAL})
endfunction()

function(add_benchmark BM_NAME)
  add_executable(${BM_NAME} ${BM_NAME}.cpp)
  append_compiler_flags(${BM_NAME})
  target_link_libraries(${BM_NAME} PRIVATE gnuradio4::gnuradio-options ut gnuradio4::ut-benchmark)
endfunction()

if(ENABLE_BENCH)
  add_benchmark(bm_example)
endif()
