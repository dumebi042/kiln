#!/usr/bin/env python3
"""Extract text from all PDFs in the Kiln audit workspace."""

import os
import sys

try:
    import fitz  # PyMuPDF
except ImportError:
    print("ERROR: PyMuPDF (fitz) is required. Install with: pip install PyMuPDF")
    sys.exit(1)

BASE_DIR = "/Users/dumebi/Downloads/Projects/bounty/kiln"
EXCLUDE = ["Kiln _ Kiln V1 Bounty bounty _ Cantina.pdf"]

def extract_pdf(pdf_path):
    """Extract all text from a PDF file."""
    text_parts = []
    try:
        doc = fitz.open(pdf_path)
        for page_num in range(len(doc)):
            page = doc[page_num]
            text = page.get_text()
            if text.strip():
                text_parts.append(f"--- Page {page_num + 1} ---\n{text}")
        doc.close()
        return "\n\n".join(text_parts)
    except Exception as e:
        return f"ERROR extracting {pdf_path}: {e}"

def main():
    pdf_files = []
    for f in os.listdir(BASE_DIR):
        if f.lower().endswith(".pdf") and f not in EXCLUDE:
            pdf_files.append(f)
    
    pdf_files.sort()
    
    print(f"Found {len(pdf_files)} PDFs to process (excluding {EXCLUDE[0]})")
    print("=" * 70)
    
    for filename in pdf_files:
        full_path = os.path.join(BASE_DIR, filename)
        file_size = os.path.getsize(full_path)
        print(f"\n{'=' * 70}")
        print(f"📄 {filename}")
        print(f"   Size: {file_size:,} bytes")
        print(f"{'=' * 70}")
        
        text = extract_pdf(full_path)
        
        if text.startswith("ERROR"):
            print(f"   ❌ {text}")
        else:
            # Show first 500 chars as preview
            preview = text[:500]
            lines = text.count('\n')
            chars = len(text)
            print(f"   ✅ Extracted: {lines} lines, {chars} characters")
            print(f"\n   --- PREVIEW (first 500 chars) ---")
            print(f"   {preview[:500]}")
            print(f"   ...")
            
            # Save extracted text to a file
            out_file = os.path.join(BASE_DIR, f"_extracted_{filename}.txt")
            with open(out_file, 'w') as f_out:
                f_out.write(text)
            print(f"   💾 Saved to: _extracted_{filename}.txt")
    
    print(f"\n{'=' * 70}")
    print("Extraction complete!")

if __name__ == "__main__":
    main()
