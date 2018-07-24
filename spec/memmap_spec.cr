require "./spec_helper"

describe Memmap do
  it "maps a read-only file" do
    File.write("test.txt", "here are a bunch of bytes for you to eat")

    file = Memmap::MapFile.new("test.txt")
    file_string = String.new(file.map, file.len)
    file_string.should eq "here are a bunch of bytes for you to eat"

    File.delete("test.txt")
  end
end
