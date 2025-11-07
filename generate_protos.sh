#!/bin/bash

# Script to generate Swift protobuf code from apple_notes.proto
# This will create Swift files that match the Apple Notes protobuf schema

# Check if protoc is installed
if ! command -v protoc &> /dev/null; then
    echo "protoc not found. Installing with brew..."
    brew install protobuf
fi

# Check if protoc-gen-swift is installed
if ! command -v protoc-gen-swift &> /dev/null; then
    echo "protoc-gen-swift not found. Installing..."
    brew install swift-protobuf
fi

# Create output directory
mkdir -p NotesToDo/Generated

# Generate Swift code from protobuf schema
echo "Generating Swift protobuf code from apple_notes.proto..."
protoc \
    --swift_out=NotesToDo/Generated \
    --swift_opt=Visibility=Public \
    NotesToDo/Protos/apple_notes.proto

if [ $? -eq 0 ]; then
    echo "✅ Successfully generated Swift protobuf code in NotesToDo/Generated/"
    echo "Generated files:"
    ls -la NotesToDo/Generated/
    
    echo ""
    echo "📝 Next steps:"
    echo "1. Add the generated files to your Xcode project"
    echo "2. Add SwiftProtobuf package dependency to Package.swift"
    echo "3. Update AppleNotesProtobufParser to use the generated types"
    echo "4. Test parsing with the proper schema"
else
    echo "❌ Failed to generate protobuf code"
    exit 1
fi