lib LibC
  MS_ASYNC      = 1
  MS_SYNC       = 4
  MS_INVALIDATE = 2
  SC_PAGESIZE   = 30

  fun msync(addr : Void*, len : SizeT, flags : Int)
end
