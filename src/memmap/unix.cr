require "./mman"

module Memmap
  extend self

  enum Flag
    Shared  = LibC::MAP_SHARED
    Private = LibC::MAP_PRIVATE
    Fixed   = LibC::MAP_FIXED
    Anon    = LibC::MAP_ANON
  end

  enum Prot
    Read      = LibC::PROT_READ
    Write     = LibC::PROT_WRITE
    ReadWrite = LibC::PROT_READ | LibC::PROT_WRITE
    None      = LibC::PROT_NONE
  end

  class MemmapError < Exception
  end

  # A memory mapped buffer backed by a specified file.
  #
  # The safest way to access the data mapped is through the `value` getter, which returns a `Slice(UInt8)`.
  # Any access through the raw pointer interface can cause segmentation faults or undefined behavior unless you're really careful,
  # while accessing the buffer through a `Slice` allows you to reap the potential benefits of using `mmap` without shooting
  # yourself in the foot because of its bound checks.
  class MapFile < IO
    {% if flag?(:x86_64) || flag?(:aarch64) %}
      PAGE_SIZE = LibC.sysconf(LibC::SC_PAGESIZE).to_u64
    {% elsif flag?(:i686) || flag?(:arm) || flag?(:win32) %}
      PAGE_SIZE = LibC.sysconf(LibC::SC_PAGESIZE).to_u32
    {% end %}

    DEFAULT_PERM = File::Permissions.new(0o644)
    @flag : Flag
    @prot : Prot
    @alignment : LibC::SizeT
    @len : LibC::SizeT
    @fd : Int32
    @map : UInt8*
    getter value : Bytes

    # Create an instance of `MapFile`.
    def initialize(@filepath : String, mode = "r", @offset : LibC::SizeT = 0)
      stat = uninitialized LibC::Stat
      if LibC.stat(@filepath.check_no_null_byte, pointerof(stat)) == 0
        @len = File.size(@filepath).to_u64
      else
        raise MemmapError.new("Error `stat`ing specified path")
      end

      @alignment = @offset % PAGE_SIZE
      aligned_offset = @offset - @alignment
      aligned_len = @len + @alignment

      @flag, @prot = parse_mode(mode)

      @fd =
        if @flag == Flag::Shared && File.writable?(@filepath)
          File.open(@filepath, mode = "r+", perm = DEFAULT_PERM).fd
        elsif File.readable?(@filepath)
          File.open(@filepath, mode = "r", perm = DEFAULT_PERM).fd
        else
          raise MemmapError.new("Unable to open file '#{@filepath}'")
        end

      @map = alloc(aligned_len, aligned_offset)
      @value = Slice.new(@map, @len)
    end

    protected def alloc(aligned_len : LibC::SizeT, aligned_offset : LibC::SizeT) : UInt8*
      ptr = LibC.mmap(Pointer(Void).null, aligned_len, @prot.value, @flag.value, @fd, aligned_offset)

      if ptr == LibC::MAP_FAILED
        raise MemmapError.new("Unable to create map")
      end

      # Cast the `void*` returned by `mmap()` to a `char*`, `UInt8*` in Crystal
      Pointer(UInt8).new(ptr.address)
    end

    def <<(appendix : Bytes)
      write(appendix)
    end

    # Append a `Slice(UInt8)`/`Bytes` to a mapped file by calling `ftruncate` on the mapped file's
    # fdesc, `lseek`ing to the 'old' end of the file, writing the `Bytes` to the file, and either
    # calling `mremap` if we're on Linux or `munmap` and then `mmap` if we're on macOS/FreeBSD/whatever.
    def write(appendix : Bytes) : Nil
      raise MemmapError.new("File not mapped with read/write permission") unless @prot = Prot::ReadWrite
      aligned_len = @alignment + @len
      new_len = aligned_len + appendix.size

      if LibC.ftruncate(@fd, new_len) == -1
        raise MemmapError.new("Error truncating file to new length")
      end
      if LibC.lseek(@fd, aligned_len, IO::Seek::Set) == -1
        raise MemmapError.new("Error lseeking to offset #{@len}")
      end
      if LibC.write(@fd, appendix.to_unsafe, appendix.size) == -1
        raise MemmapError.new("Error appending to file")
      end

      {% if flag?(:linux) %}
        ptr = LibC.mremap(@map, aligned_len, new_len, LibC::MREMAP_MAYMOVE)
        if ptr == LibC::MAP_FAILED
          raise MemmapError.new("Error remapping file")
        elsif ptr.address != @map.address
          @map = Pointer(UInt8).new(ptr.address)
        end
      {% else %}
        aligned_offset = @offset - (@offset % PAGE_SIZE)
        if LibC.munmap(@map, aligned_len) == -1
          raise MemmapError.new("Error remapping file")
        end

        ptr = LibC.mmap(@map, aligned_len, @prot.value, @flag.value, @fd, aligned_offset)
        if ptr == LibC::MAP_FAILED
          raise MemmapError.new("Error remapping file")
        end
        @map = Pointer(UInt8).new(ptr.address)
      {% end %}

      @len = new_len
      @value = Slice.new(@map, @len)
    end

    # Returns the buffer as a raw `Pointer(UInt8)`. This is unsafe, obviously.
    def as_ptr
      @map
    end

    # Flush changes made in the map back into the filesystem. Synchronous 
    # version requests an update and waits for it to complete.
    def flush
      LibC.msync(@map, @len, LibC::MS_SYNC)
    end

    # Flush changes made in the map back into the filesystem. Asynchronous 
    # version requests and update and waits for it to complete. According to 
    # the [man page for msync](https://www.man7.org/linux/man-pages/man2/msync.2.html#NOTES) 
    # this has been a noop on Linux since 2.6.19 since the kernel already tracks 
    # dirty pages.
    def flush_async
      LibC.msync(@map, @len, LibC::MS_ASYNC)
    end

    # Call `mprotect` to change the 'prot' flags to be read-only
    def make_read_only
      len = @alignment + @len
      LibC.mprotect(@map, len, Prot::Read)
    end

    # Call `mprotect` to change the 'prot' flags to allow reading and writing
    def make_writable
      len = @alignment + @len
      LibC.mprotect(@map, len, Prot::ReadWrite)
    end

    def to_s(io : IO)
      @value.to_s(io)
    end

    def read(slice : Bytes)
      slice.size.times { |i| slice[i] = @value[i] }
      slice.size
    end

    # Move the seek pointer for the mapped fdesc
    def seek(offset, whence : IO::Seek = IO::Seek::Set)
      if LibC.lseek(@fd, @alignment + @len, IO::Seek::Set) == -1
        raise MemmapError.new("Error lseeking to offset #{@len}")
      end
    end

    # Append a `Slice(UInt8)`/`Bytes` to a mapped file by writing the already-mapped buffer concatenated
    # with the new bytes to a newly allocated mapped buffer backed by a new file.
    # This relies on `ftruncate` and some pointer arithmetic to work correctly, so tread carefully.
    # If you point it in the wrong direction it will eat your data.
    def copy_append(filepath : String, appendix : Bytes) : Symbol
      len = @alignment + @len + appendix.size
      # Clean the path out and write a garbage byte in there
      File.write(filepath, "\0")
      fd = File.open(filepath, mode = "r+", perm = DEFAULT_PERM).fd

      if LibC.ftruncate(fd, len) == -1
        return :err
      end

      ptr = LibC.mmap(Pointer(Void).null, len, Prot::ReadWrite, Flag::Shared, fd, @offset)
      ptr = Pointer(UInt8).new(ptr.address)

      @map.copy_to(ptr, @alignment + @len)
      appendix.copy_to(ptr + @alignment + @len, appendix.size)
      LibC.msync(ptr, len, LibC::MS_SYNC)

      if LibC.munmap(ptr, len) == -1
        return :err
      end

      :ok
    end

    # :nodoc:
    def finalize
      close()
    end

    # Force the map to close before the GC runs `finalize`
    def close
      len = @alignment + @len
      if LibC.munmap(@map, len) == -1
        raise MemmapError.new("Error unmapping file")
      end
    end

    protected def parse_mode(mode : String)
      if mode.size == 0 || mode.size > 2
        raise "Invalid access mode"
      end

      flag = Flag::Private
      prot = Prot::None

      case mode[0]
      when 'r'
        if mode.size == 2 && mode[1] == '+'
          flag = Flag::Shared
          prot = Prot::ReadWrite
        else
          flag = Flag::Private
          prot = Prot::Read
        end
      when 'w'
        prot = Prot::Write
      end

      {flag, prot}
    end
  end
end
