(in-package #:vivace-graph)

(defmethod vivace-gc ((graph graph))
  (with-transaction ((triple-db graph))
    (loop until (sb-concurrency:queue-empty-p (delete-queue graph)) do
	 (let ((item (sb-concurrency:dequeue (delete-queue graph))))
	   (typecase item
	     (node   (if (= 0 (node-ref-count item)) (delete-node item)))
	     (triple (triple-deleted? item) (erase-triple item)))))))
