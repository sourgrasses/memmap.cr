require "./spec_helper"

describe Memmap do
  it "maps a read-only file" do
    File.write("test.txt", "here are a bunch of bytes for you to eat")

    file = Memmap::MapFile.new("test.txt")
    file_string = String.new(file.value)
    file_string.should eq "here are a bunch of bytes for you to eat"

    File.delete("test.txt")
  end

  it "maps a file and shifts every byte up by 1" do
    File.write("test.txt", "here are a bunch of bytes again")

    file = Memmap::MapFile.new("test.txt", mode = "r+")
    file.value.map! { |v| v + 1 }
    file.flush
    file.close

    File.read("test.txt").should eq "ifsf!bsf!b!cvodi!pg!czuft!bhbjo"
    File.delete("test.txt")
  end

  it "maps a file and appends to it by writing to a new file" do
    File.write("test.txt", "here are a bunch of bytes yet again")

    file = Memmap::MapFile.new("test.txt", mode = "r+")
    appendix = " and more!".to_slice
    file << appendix

    String.new(file.value).should eq "here are a bunch of bytes yet again and more!"
  end
end
