# frozen_string_literal: true
require "test_helper"

class AutoloadReloadableTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @top_level_constants = Object.constants
    AutoloadReloadable.inflector # force autoload so loaded features don't change
    @old_loaded_features = $LOADED_FEATURES.dup
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
    AutoloadReloadable.clear
    AutoloadReloadable.non_reloadable_paths.clear
    assert_equal [], Object.constants - @top_level_constants
    assert_equal [], $LOADED_FEATURES - @old_loaded_features
  end

  def test_top_level_const
    File.write(File.join(@tmpdir, "foo_bars.rb"), "class FooBars; end")
    AutoloadReloadable::Paths.push(@tmpdir)
    assert_equal Class, FooBars.class
  end

  def test_under_loaded_const
    Object.const_set(:LoadedNamespace, Module.new)
    namespace_path = File.join(@tmpdir, "loaded_namespace")
    Dir.mkdir(namespace_path)
    File.write(File.join(namespace_path, "foo.rb"), "class LoadedNamespace::Foo; end")
    AutoloadReloadable::Paths.push(@tmpdir)
    assert_equal Class, LoadedNamespace::Foo.class
    AutoloadReloadable.clear
    assert_nil defined?(LoadedNamespace::Foo)
    assert_equal "constant", defined?(LoadedNamespace)
  ensure
    Object.send(:remove_const, :LoadedNamespace) if defined?(::LoadedNamespace)
  end

  def test_nested_autoload
    File.write(File.join(@tmpdir, "outer.rb"), "class Outer; end")
    Dir.mkdir(File.join(@tmpdir, "outer"))
    File.write(File.join(@tmpdir, "outer", "nested.rb"), "class Outer::Nested; end")
    AutoloadReloadable::Paths.push(@tmpdir)
    assert_equal Class, Outer::Nested.class
    assert_equal Class, Outer.class
  end

  def test_deeply_nested_autoloads
    File.write(File.join(@tmpdir, "outer.rb"), "class Outer; end")
    Dir.mkdir(File.join(@tmpdir, "outer"))
    File.write(File.join(@tmpdir, "outer", "nested.rb"), "class Outer::Nested; end")
    Dir.mkdir(File.join(@tmpdir, "outer", "nested"))
    File.write(File.join(@tmpdir, "outer", "nested", "deep.rb"), "class Outer::Nested::Deep; end")
    AutoloadReloadable::Paths.push(@tmpdir)
    assert_equal Class, Outer::Nested::Deep.class
  end

  def test_two_paths
    Dir.mktmpdir do |dir2|
      File.write(File.join(@tmpdir, "foo.rb"), "class Foo; end")
      File.write(File.join(dir2, "bar.rb"), "class Bar; end")
      AutoloadReloadable::Paths.push(@tmpdir, dir2)
      assert_equal Class, Foo.class
      assert_equal Class, Bar.class
    end
  end

  def test_reload_const
    File.write(File.join(@tmpdir, "foo.rb"), "module Foo; def self.value; 1; end; end")
    AutoloadReloadable::Paths.push(@tmpdir)
    assert_equal 1, Foo.value
    File.write(File.join(@tmpdir, "foo.rb"), "module Foo; def self.value; 2; end; end")
    AutoloadReloadable.reload
    assert_equal 2, Foo.value
  end

  def test_reload_adds_new_const
    AutoloadReloadable::Paths.push(@tmpdir)
    File.write(File.join(@tmpdir, "foo.rb"), "class Foo; end")
    AutoloadReloadable.reload
    assert_equal Class, Foo.class
  end

  def test_reload_remove_deleted_const
    File.write(File.join(@tmpdir, "foo.rb"), "class Foo; end")
    AutoloadReloadable::Paths.push(@tmpdir)
    assert_equal Class, Foo.class
    File.delete(File.join(@tmpdir, "foo.rb"))
    AutoloadReloadable.reload
    assert_nil defined?(Foo)
  end

  def test_autoload_implicit_module
    Dir.mkdir(File.join(@tmpdir, "outer"))
    File.write(File.join(@tmpdir, "outer", "foo.rb"), "class Outer::Foo; end")
    AutoloadReloadable::Paths.push(@tmpdir)
    assert_equal Module, Outer.class
    assert_equal Class, Outer::Foo.class
  end

  def test_reload_remove_deleted_implicit_module
    Dir.mkdir(File.join(@tmpdir, "outer"))
    File.write(File.join(@tmpdir, "outer", "foo.rb"), "class Outer::Foo; end")
    AutoloadReloadable::Paths.push(@tmpdir)
    FileUtils.remove_entry(File.join(@tmpdir, "outer"))
    AutoloadReloadable.reload
    assert_nil defined?(Outer)
  end

  def test_remove_path_removes_autoload
    File.write(File.join(@tmpdir, "foo.rb"), "class Foo; end")
    AutoloadReloadable::Paths.push(@tmpdir)
    assert defined?(::Foo)
    AutoloadReloadable::Paths.clear
    assert_nil defined?(::Foo)
  end

  def test_remove_path_keeps_autoloaded
    File.write(File.join(@tmpdir, "foo.rb"), "class Foo; end")
    AutoloadReloadable::Paths.push(@tmpdir)
    assert_equal Class, Foo.class
    AutoloadReloadable::Paths.clear
    assert_equal Class, Foo.class
  end

  def test_prepend_path_overrides_prev_autoload
    dirs = %w(a b).map do |name|
      dir = File.join(@tmpdir, name)
      Dir.mkdir(dir)
      File.write(File.join(dir, "foo.rb"), "module Foo; def self.from; :#{name}; end; end")
      dir
    end
    AutoloadReloadable::Paths.push(dirs[0])
    assert_output(nil, "Multiple paths to autoload Foo:\n  #{dirs.first}/foo.rb\n  #{dirs.last}/foo.rb\n") do
      AutoloadReloadable::Paths.prepend(dirs[1])
    end
    assert_equal :b, Foo.from
  end

  def test_push_path_keeps_prev_autoload
    dirs = %w(a b).map do |name|
      dir = File.join(@tmpdir, name)
      Dir.mkdir(dir)
      File.write(File.join(dir, "foo.rb"), "module Foo; def self.from; :#{name}; end; end")
      dir
    end
    AutoloadReloadable::Paths.push(dirs.first)
    assert_output(nil, "Multiple paths to autoload Foo:\n  #{dirs.first}/foo.rb\n  #{dirs.last}/foo.rb\n") do
      AutoloadReloadable::Paths.push(dirs.last)
    end
    assert_equal :a, Foo.from
  end

  def test_eagerload
    File.write(File.join(@tmpdir, "outer.rb"), "class Outer; end")
    Dir.mkdir(File.join(@tmpdir, "outer"))
    File.write(File.join(@tmpdir, "outer", "nested.rb"), "class Outer::Nested; end")
    AutoloadReloadable::Paths.push(@tmpdir)
    AutoloadReloadable.eager_load
    assert_nil Object.autoload?(:Outer)
    assert_equal "constant", defined?(Outer::Nested)
    assert_nil Outer.autoload?(:Nested)
  end

  def test_const_nested_under_class_new
    File.write(File.join(@tmpdir, "outer.rb"), "Outer = Class.new")
    Dir.mkdir(File.join(@tmpdir, "outer"))
    File.write(File.join(@tmpdir, "outer", "nested.rb"), "class Outer::Nested; end")
    AutoloadReloadable::Paths.push(@tmpdir)
    assert_equal Class, Outer::Nested.class
    assert_equal Class, Outer.class
  end

  def test_autoload_nested_after_manual_require
    $LOAD_PATH << @tmpdir
    File.write(File.join(@tmpdir, "outer.rb"), "module Outer; end")
    Dir.mkdir(File.join(@tmpdir, "outer"))
    File.write(File.join(@tmpdir, "outer", "inner.rb"), "module Outer; class Inner; end; end")
    AutoloadReloadable::Paths.push(@tmpdir)
    require 'outer'
    assert_equal Class, Outer::Inner.class
  ensure
    $LOAD_PATH.delete(@tmpdir)
  end

  def test_reference_nested_const_from_parent
    File.write(File.join(@tmpdir, "outer.rb"), "class Outer; INNER_VALUE = Inner.value; end")
    Dir.mkdir(File.join(@tmpdir, "outer"))
    File.write(File.join(@tmpdir, "outer", "inner.rb"), "class Outer::Inner; def self.value; 1; end; end")
    AutoloadReloadable::Paths.push(@tmpdir)
    assert_equal 1, Outer::INNER_VALUE
  end

  def test_non_reloadable_paths
    filename = File.join(@tmpdir, "foo.rb")
    File.write(filename, "module Foo; def self.value; 1; end; end")
    AutoloadReloadable::Paths.push(@tmpdir)
    AutoloadReloadable.non_reloadable_paths << @tmpdir
    assert_equal 1, Foo.value
    File.write(filename, "module Foo; def self.value; 2; end; end")
    AutoloadReloadable.reload
    assert_equal 1, Foo.value
    assert $LOADED_FEATURES.include?(filename)
  ensure
    Object.send(:remove_const, :Foo) if defined?(::Foo)
    $LOADED_FEATURES.delete(filename)
  end
end
