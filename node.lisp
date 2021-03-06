(in-package #:vivace-graph)

(defstruct (node
	     (:conc-name %node-)
	     (:predicate node?))
  (uuid (make-uuid))
  (value nil))

(defgeneric lookup-node (value graph &optional serialized?))
(defgeneric make-anonymous-node-name (uuid))
(defgeneric incf-ref-count (node))
(defgeneric decf-ref-count (node))
(defgeneric save-node (node))
(defgeneric make-anonymous-node-name (uuid))
(defgeneric node-uuid (node))
(defgeneric node-value (node))
(defgeneric node-ref-count (node))

(defgeneric node-eql (n1 n2)
  (:method ((n1 node) (n2 node)) (uuid:uuid-eql (node-uuid n1) (node-uuid n2)))
  (:method (n1 n2) nil))

(defgeneric node-equal (n1 n2)
  (:method ((n1 node) (n2 node)) 
    (and (uuid:uuid-eql (node-uuid n1) (node-uuid n2))
	 (equal (node-value n1) (node-value n2))))
  (:method (n1 n2) nil))

(defmethod node-uuid ((node node))
  (if (eq (%node-uuid node) +needs-lookup+)
      (setf (%node-uuid node) 
	    (deserialize (lookup-object (triple-db *graph*) 
					(make-slot-key (node-value node) "uuid"))))
      (%node-uuid node)))

(defmethod node-value ((node node))
  (%node-value node))

(defmethod node-ref-count ((node node))
  (let ((count (lookup-object (triple-db *graph*) (make-slot-key (node-value node) "ref-count"))))
    (if (vectorp count)
	(deserialize count)
	0)))

(defmethod save-node ((node node))
  (with-transaction ((triple-db *graph*))
    (store-object (triple-db *graph*) 
		  (make-slot-key (node-value node) "value") (serialize (node-value node)))
    (store-object (triple-db *graph*) 
		  (make-slot-key (node-value node) "uuid") (serialize (node-uuid node)))
    (store-object (triple-db *graph*) 
		  (make-slot-key (node-value node) "ref-count") (serialize (node-ref-count node)))))

(defmethod cache-node ((node node))
  (setf (gethash (node-value node) (node-cache *graph*)) node))

(defmethod lookup-node ((node node) (graph graph) &optional serialized?)
  (declare (ignore serialized? graph))
  node)

(defmethod lookup-node (value (graph graph) &optional serialized?)
  (if serialized? (setq value (deserialize value)))
  (or (gethash value (node-cache graph))
      (let ((serialized-value (lookup-object (triple-db graph) (make-slot-key value "value"))))
	(if (vectorp serialized-value)
	    (let ((node (make-node :uuid +needs-lookup+ 
				   :value (deserialize serialized-value))))
	      (cache-node node))
	    nil))))

(defmethod incf-ref-count ((node node))  
  (store-object (triple-db *graph*) 
		(make-slot-key (node-value node) "ref-count") 
		(serialize (1+ (node-ref-count node)))
		:mode :replace)
  (node-ref-count node))

(defmethod decf-ref-count ((node node))
  (store-object (triple-db *graph*)
		(make-slot-key (node-value node) "ref-count") 
		(serialize (1- (node-ref-count node)))
		:mode :replace)
  (let ((count (node-ref-count node)))
    (if (= 0 count) (sb-concurrency:enqueue node (delete-queue *graph*)))
    count))

(defun list-nodes (&optional graph)
  "FIXME: update for tokyo cabinet-based store."
  (declare (ignore graph))
;  (let ((*graph* (or graph *graph*)) (result nil))
;    (map-skip-list-values #'(lambda (node) (push node result)) (nodes *graph*))
;    (reverse result)))
  )

(defmethod make-anonymous-node-name ((uuid uuid:uuid))
  (format nil "_anon:~A" uuid))

(defun make-anonymous-node (&key graph)
  (let ((*graph* (or graph *graph*)))
    (let* ((uuid (make-uuid)) 
	   (value (make-anonymous-node-name uuid)))
      (let ((node (make-node :uuid uuid 
			     :value value)))
	(save-node node)
	node))))

(defun make-new-node (&key value graph (cache? t))
  (if (node? value)
      value
      (let ((*graph* (or graph *graph*)))
	(or (lookup-node value *graph*)
	    (let ((node (make-node :value value)))
	      (handler-case
		  (save-node node)
		(persistence-error (condition)
		  (declare (ignore condition))
		  (lookup-node value *graph*))
		(:no-error (status)
		  (declare (ignore status))
		  (when cache? (cache-node node))
		  node)))))))

(defmethod delete-node ((node node))
  (with-transaction ((triple-db *graph*))
    node))

