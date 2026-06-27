(import (scheme base) (scheme write) (kaappi bdd))

(describe "LLVM backend target expressions"
  (describe "arithmetic"
    (it "folds constant addition"
      (expect (+ 1 2) to-equal 3))

    (it "handles subtraction"
      (expect (- 10 3) to-equal 7))

    (it "handles multiplication"
      (expect (* 4 5) to-equal 20))

    (it "handles nested arithmetic"
      (expect (+ (* 2 3) (- 10 4)) to-equal 12)))

  (describe "display values"
    (it "converts fixnums to strings"
      (expect (number->string 42) to-equal "42"))

    (it "converts negative fixnums"
      (expect (number->string -7) to-equal "-7"))

    (it "concatenates strings"
      (expect (string-append "hello" " world") to-equal "hello world")))

  (describe "boolean logic"
    (it "evaluates true"
      (expect #t to-be-truthy))

    (it "evaluates false"
      (expect #f to-be-falsy))

    (it "evaluates not"
      (expect (not #f) to-be-truthy))))

(run-specs)
