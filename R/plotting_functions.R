
#' Convert a list of fragments to cut sites or Tn5 footprints
#'
#' @param fragment_list A list of GenomicRanges objects containing fragment regions
#' @param to The type of regions to convert to. Can be "cuts", which are the 5' ends of each region, or "footprints",
#' which are the 19 bp footprint regions of the Tn5 transposase.
#'
#' @return A list of the same length of fragment_list, with objects converted to cuts or footprints.
#' @export
#'
convert_fragment_list <- function(fragment_list,
                                  to = c("cuts","footprints")) {
  out_list <- list()
  if(to == "cuts") {
    for(i in 1:length(fragment_list)) {
      prime5 <- fragment_list[[i]]
      end(prime5) <- BiocGenerics::start(prime5)
      prime3 <- fragment_list[[i]]
      start(prime3) <- BiocGenerics::end(prime3)
      out_list[[i]] <- GenomicRanges::sort(c(prime5,prime3))
      names(out_list)[i] <- names(fragment_list)[i]
    }
  } else if(to == "footprints") {
    for(i in 1:length(fragment_list)) {
      prime5 <- fragment_list[[i]]
      end(prime5) <- BiocGenerics::start(prime5) + 19
      start(prime5) <- BiocGenerics::start(prime5) -10
      prime3 <- fragment_list[[i]]
      start(prime3) <- BiocGenerics::end(prime3) - 18
      end(prime3) <- BiocGenerics::end(prime3) + 10
      both <- c(prime5,prime3)
      start(both)[start(both) < 1] <- 1
      out_list[[i]] <- BiocGenerics::sort(both)
      names(out_list)[i] <- names(fragment_list)[i]
    }
  }
  out_list
}

#' Pileup reads, fragments, or cuts from a BAM file over target GRanges regions.
#'
#' @param gr_list A list of GRanges objects
#' @param gr_target A single GRanges object for the target region to plot.
#' @param gr_groups A vector indicating which group each GRanges object in gr_list belongs to. If NULL, will group all samples into a single track.
#' @param norm Normalization for each group. Currently support is per-million ("PM") and "max".
#' @param window_size Window bin size to use for region down-sampling. If NULL, will not downsample.
#' @param window_mode If using window_size, what value to use for each window. Options are "max","mean", and "median".
#'
#' @return list of data.frames, one per group in gr_groups. Each data.frame has pos (position) and val (value) columns.
#' @export
#'
pileup_gr_list <- function(gr_list,
                           gr_target,
                           gr_groups = NULL,
                           norm = c("PM","max"),
                           window_size = NULL,
                           window_mode = c("max","mean","median")) {

  if(is.null(gr_groups)) {
    gr_groups <- 1
    groups <- 1
  } else {
    groups <- unique(gr_groups)
  }

  out_list <- list()

  gr_target <- gr_target[1]
  target_chr <- as.character(GenomicRanges::seqnames(gr_target))
  target_ranges <- GenomicRanges::ranges(gr_target)
  target_start <- GenomicRanges::start(gr_target)
  target_end <- GenomicRanges::end(gr_target)

  for(i in 1:length(groups)) {

    group <- groups[i]
    group_gr <- gr_list[gr_groups == group]

    chr_list <- lapply(group_gr,
                       function(x) {
                         GenomicRanges::ranges(x[as.character(GenomicRanges::seqnames(x)) == target_chr])
                       })

    ol_list <- lapply(chr_list,
                      function(x) {
                        IRanges::subsetByOverlaps(x, target_ranges)
                      })

    ol_lens <- lapply(ol_list, length)

    ol_list <- ol_list[ol_lens > 0]

    if(length(ol_list) == 0) {
      pile <- data.frame(pos = target_start:target_end,
                         val = 0)
    } else {

      ol_ranges <- ol_list[[1]]

      if(length(ol_list) > 1) {
        for(j in 2:length(ol_list)) {
          ol_ranges <- c(ol_ranges, ol_list[[j]])
        }
      }

      ol_coverage <- IRanges::coverage(ol_ranges,
                                       shift = -1 * target_start,
                                       width = target_end - target_start + 1)

      pile <- data.frame(pos = target_start:target_end,
                         val = rep(ol_coverage@values, ol_coverage@lengths))

    }


    if(!is.null(window_size)) {
      pile <- pile %>%
        mutate(bin = floor(pos/window_size))
      if(window_mode == "max") {
        pile <- pile %>%
          group_by(bin) %>%
          summarise(pos = bin[1]*window_size,
                    val = max(val))
      } else if(window_mode == "mean") {
        pile <- pile %>%
          group_by(bin) %>%
          summarise(pos = bin[1]*window_size,
                    val = mean(val))
      } else if(window_mode == "max") {
        pile <- pile %>%
          group_by(bin) %>%
          summarise(pos = bin[1]*window_size,
                    val = median(val))
      }

      pile <- pile %>%
        select(pos, val)
    }

    if(norm == "PM") {
      m <- sum(unlist(lapply(group_gr,length)))
      pile$val <- pile$val/m*1e6
    } else if(norm == "max") {
      pile$val <- pile$val/max(pile$val)
    }

    out_list[[i]] <- pile
  }
  names(out_list) <- groups


  if(length(groups) == 1) {
    out_list <- out_list[[1]]
  }

  out_list

}


#' Build a multi-track pileup plot
#'
#' @param gr_list A list of GRanges objects
#' @param ucsc_loc A target location, in UCSC format (e.g. "chr1:533,235-552,687)
#' @param highlight_loc A location to use for highlights in UCSC format
#' @param padding A 2-element numeric vector with upstream and downstream padding around the ucsc_loc to extend the plotting window.
#' @param gr_groups A vector indicating which group each GRanges object in gr_list belongs to. If NULL, will group all samples into a single track.
#' @param group_colors A named vector, one per group, with colors for each group. Names should match values in gr_groups.
#' @param norm Normalization for each group. Currently support is per-million ("PM") and "max".
#' @param max_val A maximum value to use for scaling the y-values in each track.
#' @param window_size Window bin size to use for region down-sampling. If NULL, will not downsample.
#' @param window_mode If using window_size, what value to use for each window. Options are "max","mean", and "median".
#' @param target_color The color of the background rectangle to highlight the region in ucsc_loc.
#' @param highlight_color The color the background rectangle to highlight the region in highlight_loc.
#'
#' @return A ggplot2 plot object
#' @export
build_pile_plot <- function(gr_list,
                            ucsc_loc,
                            highlight_loc = NULL,
                            padding = c(1e5,1e5),
                            gr_groups = NULL,
                            group_colors = NULL, #named vector
                            norm = c("PM","max"),
                            max_val = NULL,
                            window_size = NULL,
                            window_mode = c("max","mean","median"),
                            target_color = "#B7B7B7",
                            highlight_color = "#F9ED32") {

  gr_target <- ucsc_loc_to_GRanges(ucsc_loc)
  target_start <- start(gr_target)
  target_end <- end(gr_target)

  start(gr_target) <- start(gr_target) - padding[1]
  end(gr_target) <- end(gr_target) + padding[2]

  piles <- pileup_gr_list(gr_list,
                           gr_target,
                           gr_groups,
                           norm,
                           window_size,
                           window_mode)

  target_rect <- data.frame(xmin = target_start,
                            xmax = target_end,
                            ymin = 1,
                            ymax = length(piles) + 1,
                            fill = target_color)

  chr <- as.character(seqnames(gr_target))


  pile_plot <- ggplot() +
    theme_classic() +
    scale_x_continuous(chr, expand = c(0,0)) +
    scale_y_continuous("", expand = c(0,0)) +
    theme(axis.text.y = element_blank(),
          axis.ticks.y = element_blank(),
          axis.line.y = element_blank()) +
    scale_color_identity() +
    scale_fill_identity() +
    geom_rect(data = target_rect,
              aes(xmin = xmin, xmax = xmax,
                  ymin = ymin, ymax = ymax,
                  fill = fill))

  if(!is.null(highlight_loc)) {
    hi_target <- ucsc_loc_to_GRanges(highlight_loc)
    hi_start <- start(hi_target)
    hi_end <- end(hi_target)

    hi_rect <- data.frame(xmin = hi_start,
                          xmax = hi_end,
                          ymin = 1,
                          ymax = length(piles) + 1,
                          fill = highlight_color)

    pile_plot <- pile_plot +
      geom_rect(data = hi_rect,
                aes(xmin = xmin, xmax = xmax,
                    ymin = ymin, ymax = ymax,
                    fill = fill))

  }

  if(is.null(max_val)) {
    max_val <- max(unlist(lapply(piles, function(x) max(x$val))))
  }

  for(i in 1:length(piles)) {
    pile <- piles[[i]]
    pile_color <- group_colors[names(group_colors) == names(piles)[i]]

    baseline <- data.frame(x = start(gr_target),
                           xend = end(gr_target),
                           y = i,
                           yend = i,
                           color = pile_color)

    pile_plot <- pile_plot +
      geom_segment(data = baseline,
                   aes(x = x, xend = xend,
                       y = y, yend = y,
                       color = color),
                   size = 0.1)

    if(!is.null(pile)) {
      pile$val <- i + pile$val / max_val
      pile$min <- i

      pile$val[pile$val > i + 1] <- i + 1
      pile_plot <- pile_plot +
        geom_ribbon(data = pile,
                    aes(x = pos, ymin = min, ymax = val),
                    color = NA,
                    fill = pile_color)
    }




  }

  pile_plot
}

#' Build a multi-track pileup heatmap
#'
#' @param gr_list A list of GRanges objects
#' @param ucsc_loc A target location, in UCSC format (e.g. "chr1:533,235-552,687)
#' @param highlight_loc A location to use for highlights in UCSC format
#' @param padding A 2-element numeric vector with upstream and downstream padding around the ucsc_loc to extend the plotting window.
#' @param gr_groups A vector indicating which group each GRanges object in gr_list belongs to. If NULL, will group all samples into a single track.
#' @param colorset A vector of colors used to generate the heamtap colorscale. Default is c("white","black")
#' @param norm Normalization for each group. Currently support is per-million ("PM") and "max".
#' @param max_val A maximum value to use for scaling the y-values in each track.
#' @param window_size Window bin size to use for region down-sampling. If NULL, will not downsample.
#' @param window_mode If using window_size, what value to use for each window. Options are "max","mean", and "median".
#' @param target_color The color of the background rectangle to highlight the region in ucsc_loc.
#' @param highlight_color The color the background rectangle to highlight the region in highlight_loc.
#' @param baselines Logical, whether or not to separate tracks with a line.
#'
#' @return A ggplot2 plot object
#' @export
build_pile_heatmap <- function(gr_list,
                               ucsc_loc,
                               highlight_loc = NULL,
                               padding = c(1e5,1e5),
                               gr_groups = NULL,
                               colorset = c("white","black"),
                               norm = "PM",
                               max_val = NULL,
                               window_size = NULL,
                               window_mode = c("max","mean","median"),
                               target_color = "#CBF8FF",
                               highlight_color = "#F9ED32",
                               baselines = TRUE) {

  gr_target <- ucsc_loc_to_GRanges(ucsc_loc)
  target_start <- start(gr_target)
  target_end <- end(gr_target)

  start(gr_target) <- start(gr_target) - padding[1]
  end(gr_target) <- end(gr_target) + padding[2]

  piles <- pileup_gr_list(gr_list,
                          gr_target,
                          gr_groups,
                          norm,
                          window_size,
                          window_mode)

  target_rect <- data.frame(xmin = target_start,
                            xmax = target_end,
                            ymin = 1,
                            ymax = length(piles) + 1,
                            fill = target_color)

  chr <- as.character(seqnames(gr_target))


  pile_plot <- ggplot() +
    theme_classic() +
    scale_x_continuous(chr, expand = c(0,0)) +
    scale_y_continuous("", expand = c(0,0)) +
    theme(axis.text.y = element_blank(),
          axis.ticks.y = element_blank(),
          axis.line.y = element_blank()) +
    scale_color_identity() +
    scale_fill_identity() +
    geom_rect(data = target_rect,
              aes(xmin = xmin, xmax = xmax,
                  ymin = ymin, ymax = ymax,
                  fill = fill))

  if(!is.null(highlight_loc)) {
    hi_target <- ucsc_loc_to_GRanges(highlight_loc)
    hi_start <- start(hi_target)
    hi_end <- end(hi_target)

    hi_rect <- data.frame(xmin = hi_start,
                          xmax = hi_end,
                          ymin = 1,
                          ymax = length(piles) + 1,
                          fill = highlight_color)

    pile_plot <- pile_plot +
      geom_rect(data = hi_rect,
                aes(xmin = xmin, xmax = xmax,
                    ymin = ymin, ymax = ymax,
                    fill = fill))

  }

  if(is.null(max_val)) {
    max_val <- max(unlist(lappy(piles, function(x) max(x$val))))
  }

  for(i in 1:length(piles)) {
    pile <- piles[[i]]
    #pile_color <- group_colors[names(group_colors) == names(piles)[i]]

    pile$val <- pile$val / max_val

    baseline <- data.frame(x = min(pile$pos),
                           xend = max(pile$pos),
                           y = i,
                           yend = i,
                           color = "#000000")
    pile <- pile %>%
      filter(val > 0)

    pile$ypos <- i

    pile$color <- values_to_colors(pile$val,
                                   min_val = 0,
                                   max_val = 1,
                                   colorset = colorset)

    if(baselines) {
      pile_plot <- pile_plot +
        geom_segment(data = baseline,
                     aes(x = x, xend = xend,
                         y = y, yend = y,
                         color = color),
                     size = 0.1)
    }

    pile_plot <- pile_plot +
      geom_rect(data = pile,
                aes(xmin = pos,
                    xmax = pos + window_size,
                    ymin = ypos + 0.05,
                    ymax = ypos + 0.95,
                    fill = color),
                color = NA)
  }

  pile_plot
}
