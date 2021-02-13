lib LibC
  MS_ASYNC      = 1
  MS_SYNC       = 4
  MS_INVALIDATE = 2
  # SC_PAGESIZE   = 30

  MREMAP_MAYMOVE    = 1
  MREMAP_FIXED      = 2

  fun msync(addr : Void*, len : SizeT, flags : Int)

  {% if flag?(:linux) %}
    fun mremap(old_addr : Void*, old_size : SizeT, new_size : SizeT, flags : Int) : Void*
  {% end %}
end
