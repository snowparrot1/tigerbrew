require "formula"

class Gcc < Formula
  def arch
    if Hardware::CPU.type == :intel
      if MacOS.prefer_64_bit?
        "x86_64"
      else
        "i686"
      end
    elsif Hardware::CPU.type == :ppc
      if MacOS.prefer_64_bit?
        "powerpc64"
      else
        "powerpc"
      end
    end
  end

  def osmajor
    `uname -r`.chomp
  end

  homepage "http://gcc.gnu.org"
  url "http://ftpmirror.gnu.org/gcc/gcc-4.8.2/gcc-4.8.2.tar.bz2"
  mirror "ftp://gcc.gnu.org/pub/gcc/releases/gcc-4.8.2/gcc-4.8.2.tar.bz2"
  sha1 "810fb70bd721e1d9f446b6503afe0a9088b62986"
  revision 1

  head "svn://gcc.gnu.org/svn/gcc/branches/gcc-4_8-branch"

  bottle do
    sha1 "aacd8626960670beedf85ad13f96784f08e122a6" => :mavericks
    sha1 "fa80b7165d621fed7df413a676025aecf7faaff1" => :mountain_lion
    sha1 "5e0b1fd8dabc07f77eb2b5a1c61e0257e98c3918" => :lion
  end

  option "with-java", "Build the gcj compiler"
  option "with-all-languages", "Enable all compilers and languages, except Ada"
  option "with-nls", "Build with native language support (localization)"
  option "with-profiled-build", "Make use of profile guided optimization when bootstrapping GCC"
  option "without-fortran", "Build without the gfortran compiler"
  # enabling multilib on a host that can't run 64-bit results in build failures
  option "without-multilib", "Build without multilib support" if MacOS.prefer_64_bit?

  depends_on "gmp"
  depends_on "libmpc"
  depends_on "mpfr"
  depends_on "cloog"
  depends_on "isl"
  depends_on "ecj" if build.with?("java") || build.with?("all-languages")

  # The as that comes with Tiger isn't capable of dealing with the
  # PPC asm that comes in libitm
  depends_on "cctools" => :build if MacOS.version < :leopard

  fails_with :gcc_4_0

  # GCC 4.8.1 incorrectly determines that _Unwind_GetIPInfo is available on
  # Tiger, resulting in a failed build
  # Fixed upstream: http://gcc.gnu.org/bugzilla/show_bug.cgi?id=58710
  def patches; DATA; end if MacOS.version < :leopard

  # GCC bootstraps itself, so it is OK to have an incompatible C++ stdlib
  cxxstdlib_check :skip

  # The bottles are built on systems with the CLT installed, and do not work
  # out of the box on Xcode-only systems due to an incorrect sysroot.
  def pour_bottle?
    MacOS::CLT.installed?
  end

  def install
    # GCC will suffer build errors if forced to use a particular linker.
    ENV.delete "LD"

    if MacOS.version < :leopard
      ENV["AS"] = ENV["AS_FOR_TARGET"] = "#{Formula["cctools"].bin}/as"
    end

    # C, C++, ObjC compilers are always built
    languages = %w[c c++ objc obj-c++]

    # Everything but Ada, which requires a pre-existing GCC Ada compiler
    # (gnat) to bootstrap. GCC 4.6.0 add go as a language option, but it is
    # currently only compilable on Linux.
    languages << "fortran" if build.with?("fortran") || build.with?("all-languages")
    languages << "java" if build.with?("java") || build.with?("all-languages")

    args = [
      "--build=#{arch}-apple-darwin#{osmajor}",
      "--prefix=#{prefix}",
      "--enable-languages=#{languages.join(",")}",
      "--with-gmp=#{Formula["gmp"].opt_prefix}",
      "--with-mpfr=#{Formula["mpfr"].opt_prefix}",
      "--with-mpc=#{Formula["libmpc"].opt_prefix}",
      "--with-cloog=#{Formula["cloog"].opt_prefix}",
      "--with-isl=#{Formula["isl"].opt_prefix}",
      "--with-system-zlib",
      # This ensures lib, libexec, include are sandboxed so that they
      # don't wander around telling little children there is no Santa
      # Claus.
      "--enable-version-specific-runtime-libs",
      "--enable-libstdcxx-time=yes",
      "--enable-stage1-checking",
      "--enable-checking=release",
      "--enable-lto",
      # A no-op unless --HEAD is built because in head warnings will
      # raise errors. But still a good idea to include.
      "--disable-werror"
    ]

    # "Building GCC with plugin support requires a host that supports
    # -fPIC, -shared, -ldl and -rdynamic."
    args << "--enable-plugin" if MacOS.version > :tiger

    # Otherwise make fails during comparison at stage 3
    # See: http://gcc.gnu.org/bugzilla/show_bug.cgi?id=45248
    args << "--with-dwarf2" if MacOS.version < :leopard

    args << "--disable-nls" if build.without? "nls"

    if build.with?("java") || build.with?("all-languages")
      args << "--with-ecj-jar=#{Formula["ecj"].opt_prefix}/share/java/ecj.jar"
    end

    if build.without?("multilib") || !MacOS.prefer_64_bit?
      args << "--disable-multilib"
    else
      args << "--enable-multilib"
    end

    mkdir "build" do
      unless MacOS::CLT.installed?
        # For Xcode-only systems, we need to tell the sysroot path.
        # "native-system-header's will be appended
        args << "--with-native-system-header-dir=/usr/include"
        args << "--with-sysroot=#{MacOS.sdk_path}"
      end

      system "../configure", *args

      if build.with? "profiled-build"
        # Takes longer to build, may bug out. Provided for those who want to
        # optimise all the way to 11.
        system "make", "profiledbootstrap"
      else
        system "make", "bootstrap"
      end

      # At this point `make check` could be invoked to run the testsuite. The
      # deja-gnu and autogen formulae must be installed in order to do this.

      system "make", "install"
    end

    # Add a version suffix for backwards compatability.
    version_suffix = version.to_s.slice(/\d\.\d/)
    bin.install_symlink bin/"gcc" => "gcc-#{version_suffix}"
    bin.install_symlink bin/"g++" => "g++-#{version_suffix}"
  end

  test do
    if build.with?("fortran")
      fixture = <<-EOS.undent
        integer,parameter::m=10000
        real::a(m), b(m)
        real::fact=0.5

        do concurrent (i=1:m)
          a(i) = a(i) + fact*b(i)
        end do
        print *, "done"
        end
      EOS
      (testpath/"in.f90").write(fixture)
      system "#{bin}/gfortran", "-c", "in.f90"
      system "#{bin}/gfortran", "-o", "test", "in.o"
      assert_equal "done", `./test`.strip
    end
  end
end

__END__
diff --git a/libbacktrace/backtrace.c b/libbacktrace/backtrace.c
index 428f53a..a165197 100644
--- a/libbacktrace/backtrace.c
+++ b/libbacktrace/backtrace.c
@@ -35,6 +35,14 @@ POSSIBILITY OF SUCH DAMAGE.  */
 #include "unwind.h"
 #include "backtrace.h"

+#ifdef __APPLE__
+/* On MacOS X, versions older than 10.5 don't export _Unwind_GetIPInfo.  */
+#undef HAVE_GETIPINFO
+#if __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ >= 1050
+#define HAVE_GETIPINFO 1
+#endif
+#endif
+
 /* The main backtrace_full routine.  */

 /* Data passed through _Unwind_Backtrace.  */
diff --git a/libbacktrace/simple.c b/libbacktrace/simple.c
index b03f039..9f3a945 100644
--- a/libbacktrace/simple.c
+++ b/libbacktrace/simple.c
@@ -35,6 +35,14 @@ POSSIBILITY OF SUCH DAMAGE.  */
 #include "unwind.h"
 #include "backtrace.h"

+#ifdef __APPLE__
+/* On MacOS X, versions older than 10.5 don't export _Unwind_GetIPInfo.  */
+#undef HAVE_GETIPINFO
+#if __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ >= 1050
+#define HAVE_GETIPINFO 1
+#endif
+#endif
+
 /* The simple_backtrace routine.  */

 /* Data passed through _Unwind_Backtrace.  */
diff --git a/libgcc/unwind-c.c b/libgcc/unwind-c.c
index b937d9d..1121dce 100644
--- a/libgcc/unwind-c.c
+++ b/libgcc/unwind-c.c
@@ -30,6 +30,14 @@ see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see
 #define NO_SIZE_OF_ENCODED_VALUE
 #include "unwind-pe.h"

+#ifdef __APPLE__
+/* On MacOS X, versions older than 10.5 don't export _Unwind_GetIPInfo.  */
+#undef HAVE_GETIPINFO
+#if __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ >= 1050
+#define HAVE_GETIPINFO 1
+#endif
+#endif
+
 typedef struct
 {
   _Unwind_Ptr Start;
diff --git a/libgfortran/runtime/backtrace.c b/libgfortran/runtime/backtrace.c
index 3b58118..9a00066 100644
--- a/libgfortran/runtime/backtrace.c
+++ b/libgfortran/runtime/backtrace.c
@@ -40,6 +40,14 @@ see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see
 #include "unwind.h"


+#ifdef __APPLE__
+/* On MacOS X, versions older than 10.5 don't export _Unwind_GetIPInfo.  */
+#undef HAVE_GETIPINFO
+#if __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ >= 1050
+#define HAVE_GETIPINFO 1
+#endif
+#endif
+
 /* Macros for common sets of capabilities: can we fork and exec, and
    can we use pipes to communicate with the subprocess.  */
 #define CAN_FORK (defined(HAVE_FORK) && defined(HAVE_EXECVE) \
diff --git a/libgo/runtime/go-unwind.c b/libgo/runtime/go-unwind.c
index c669a3c..9e848db 100644
--- a/libgo/runtime/go-unwind.c
+++ b/libgo/runtime/go-unwind.c
@@ -18,6 +18,14 @@
 #include "go-defer.h"
 #include "go-panic.h"

+#ifdef __APPLE__
+/* On MacOS X, versions older than 10.5 don't export _Unwind_GetIPInfo.  */
+#undef HAVE_GETIPINFO
+#if __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ >= 1050
+#define HAVE_GETIPINFO 1
+#endif
+#endif
+
 /* The code for a Go exception.  */

 #ifdef __ARM_EABI_UNWINDER__
diff --git a/libobjc/exception.c b/libobjc/exception.c
index 4b05611..8ff70f9 100644
--- a/libobjc/exception.c
+++ b/libobjc/exception.c
@@ -31,6 +31,14 @@ see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see
 #include "unwind-pe.h"
 #include <string.h> /* For memcpy */

+#ifdef __APPLE__
+/* On MacOS X, versions older than 10.5 don't export _Unwind_GetIPInfo.  */
+#undef HAVE_GETIPINFO
+#if __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ >= 1050
+#define HAVE_GETIPINFO 1
+#endif
+#endif
+
 /* 'is_kind_of_exception_matcher' is our default exception matcher -
    it determines if the object 'exception' is of class 'catch_class',
    or of a subclass.  */