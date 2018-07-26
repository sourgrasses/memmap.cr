require "./spec_helper"

describe Memmap do
  it "maps a read-only file" do
    File.write("test.txt", "here are a bunch of bytes for you to eat")

    file = Memmap::MapFile.new("test.txt")
    file_string = String.new(file.map, file.len)
    file_string.should eq "here are a bunch of bytes for you to eat"

    File.delete("test.txt")
  end

  it "maps a file and appends some junk to it" do
    File.write("test.txt", "here are a bunch of bytes again")

    file = Memmap::MapFile.new("test.txt", mode="r+")
    appender = file.map.appender()
    "bytes bytes bytes".bytes.each do |b|
      appender << b
    end
    file.flush()
    file.close()

    File.read("test.txt").should eq "bytes bytes bytesof bytes again"
    File.delete("test.txt")
  end
end
