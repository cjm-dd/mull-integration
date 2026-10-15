#include "examples/arithmetic.h"
#include "examples/generated.h"

#include <cstdlib>
#include <fstream>
#include <string>

#include "gtest/gtest.h"

TEST(Arithmetic, Integer) { EXPECT_EQ(add(5, 3), 8); }

TEST(Arithmetic, FloatingPoint) {
#ifdef WEAK_ASSERTIONS
  EXPECT_GT(increment(2.0), 0.0);  // Both +1 and -1 satisfy this weak assertion.
#else
  EXPECT_DOUBLE_EQ(increment(2.0), 3.0);
#endif
}

TEST(Arithmetic, UncoveredBranch) {
  // Keep this function in the binary without executing it during a normal run.
  if (std::getenv("EXAMPLE_EXERCISE_UNCOVERED")) {
    EXPECT_EQ(uncovered(4), 5);
  }
}

TEST(Arithmetic, EnvironmentAndRunfiles) {
  EXPECT_EQ(kGeneratedValue, 42);
  ASSERT_NE(std::getenv("EXAMPLE_TEST_ENV"), nullptr);
  EXPECT_STREQ(std::getenv("EXAMPLE_TEST_ENV"), "forwarded");
  ASSERT_NE(std::getenv("TEST_SRCDIR"), nullptr);
  ASSERT_NE(std::getenv("TEST_WORKSPACE"), nullptr);
  std::ifstream input(std::string(std::getenv("TEST_SRCDIR")) + "/" +
                      std::getenv("TEST_WORKSPACE") + "/examples/fixture.txt");
  std::string value;
  std::getline(input, value);
  EXPECT_EQ(value, "runfiles are preserved");
}
